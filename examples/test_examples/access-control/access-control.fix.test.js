import { expect } from "chai";
import hre from "hardhat";

describe("Access control module: fixed treasury", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deployAccessControlFixedFixture() {
    // Create a realistic actor set for normal and malicious flows.
    const { ethers } = connection;
    const [owner, alice, bob, attackerOperator, coldWallet] =
      await ethers.getSigners();

    const fixedFactory = await ethers.getContractFactory("RoleBasedTreasury");
    const fixedTreasury = await fixedFactory.deploy(owner.address);
    await fixedTreasury.waitForDeployment();

    const attackerFactory = await ethers.getContractFactory("TxOriginPhishingAttacker");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy(await fixedTreasury.getAddress());
    await attackerContract.waitForDeployment();

    // Fund the treasury with multiple deposits to simulate real usage.
    await fixedTreasury.connect(owner).deposit({ value: ethers.parseEther("3") });
    await fixedTreasury.connect(alice).deposit({ value: ethers.parseEther("4") });
    await fixedTreasury.connect(bob).deposit({ value: ethers.parseEther("5") });

    return {
      ethers,
      owner,
      alice,
      bob,
      attackerOperator,
      coldWallet,
      fixedTreasury,
      attackerContract,
    };
  }

  it("blocks a tx.origin phishing attack and preserves treasury funds", async function () {
    const { networkHelpers } = connection;
    const { ethers, owner, fixedTreasury, attackerContract } =
      await networkHelpers.loadFixture(deployAccessControlFixedFixture);

    expect(await fixedTreasury.treasuryBalance()).to.equal(
      ethers.parseEther("12")
    );

    // Even if the real owner calls the attacker contract, msg.sender inside the treasury
    // is still the attacker contract, not the owner.
    await expect(attackerContract.connect(owner).claimReward()).to.be.revertedWith(
      "Only owner"
    );

    expect(await fixedTreasury.treasuryBalance()).to.equal(
      ethers.parseEther("12")
    );
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.equal(0n);
  });

  it("still allows legitimate administration through direct owner calls and two-step ownership transfer", async function () {
    const { networkHelpers } = connection;
    const { ethers, owner, alice, coldWallet, fixedTreasury } =
      await networkHelpers.loadFixture(deployAccessControlFixedFixture);

    // The owner can safely transfer ownership in a deliberate two-step flow.
    await fixedTreasury.connect(owner).transferOwnership(alice.address);
    await fixedTreasury.connect(alice).acceptOwnership();

    expect(await fixedTreasury.owner()).to.equal(alice.address);
    expect(await fixedTreasury.pendingOwner()).to.equal(
      ethers.ZeroAddress
    );

    const coldWalletBalanceBefore = await ethers.provider.getBalance(
      coldWallet.address
    );

    const sweepTx = await fixedTreasury.connect(alice).sweepTo(coldWallet.address);
    const receipt = await sweepTx.wait();
    const gasUsed = receipt.gasUsed * receipt.gasPrice;

    const coldWalletBalanceAfter = await ethers.provider.getBalance(
      coldWallet.address
    );

    expect(await fixedTreasury.treasuryBalance()).to.equal(0n);
    expect(coldWalletBalanceAfter).to.equal(
      coldWalletBalanceBefore + ethers.parseEther("12")
    );

    // Alice paid gas for the privileged operation, so we confirm ownership behavior rather than her net ETH gain.
    expect(gasUsed > 0n).to.equal(true);
  });
});
