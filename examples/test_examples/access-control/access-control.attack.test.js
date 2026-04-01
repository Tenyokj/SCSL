import { anyValue } from "@nomicfoundation/hardhat-ethers-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";

describe("Access control module: tx.origin vulnerability", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deployAccessControlVulnerableFixture() {
    // Create a realistic actor set:
    // treasury owner, two users funding the treasury, and the attacker operator.
    const { ethers } = connection;
    const [owner, alice, bob, attackerOperator, recoveryWallet] =
      await ethers.getSigners();

    // Deploy the vulnerable treasury with a real owner.
    const vulnerableFactory = await ethers.getContractFactory("OriginBasedTreasury");
    const vulnerableTreasury = await vulnerableFactory.deploy(owner.address);
    await vulnerableTreasury.waitForDeployment();

    // Deploy the attacker contract controlled by the malicious operator.
    const attackerFactory = await ethers.getContractFactory("TxOriginPhishingAttacker");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy(await vulnerableTreasury.getAddress());
    await attackerContract.waitForDeployment();

    // Honest users and the owner deposit Ether into the treasury.
    await vulnerableTreasury.connect(owner).deposit({ value: ethers.parseEther("3") });
    await vulnerableTreasury.connect(alice).deposit({ value: ethers.parseEther("4") });
    await vulnerableTreasury.connect(bob).deposit({ value: ethers.parseEther("5") });

    return {
      ethers,
      owner,
      alice,
      bob,
      attackerOperator,
      recoveryWallet,
      vulnerableTreasury,
      attackerContract,
    };
  }

  it("lets an attacker drain the treasury when the owner is tricked into calling a phishing contract", async function () {
    const { networkHelpers } = connection;
    const { ethers, owner, vulnerableTreasury, attackerContract } =
      await networkHelpers.loadFixture(deployAccessControlVulnerableFixture);

    expect(await vulnerableTreasury.treasuryBalance()).to.equal(
      ethers.parseEther("12")
    );

    // The owner is socially engineered into calling a fake reward function.
    await expect(attackerContract.connect(owner).claimReward())
      .to.emit(attackerContract, "PhishingTriggered")
      .withArgs(owner.address);

    // The vulnerable treasury is fully drained into the attacker contract.
    expect(await vulnerableTreasury.treasuryBalance()).to.equal(0n);
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.equal(ethers.parseEther("12"));
  });

  it("allows the attacker operator to cash out after the phishing-based drain", async function () {
    const { networkHelpers } = connection;
    const { ethers, owner, attackerOperator, vulnerableTreasury, attackerContract } =
      await networkHelpers.loadFixture(deployAccessControlVulnerableFixture);

    await attackerContract.connect(owner).claimReward();

    const operatorBalanceBefore = await ethers.provider.getBalance(attackerOperator.address);

    const cashoutTx = await attackerContract
      .connect(attackerOperator)
      .withdrawLoot();
    const receipt = await cashoutTx.wait();
    const gasUsed = receipt.gasUsed * receipt.gasPrice;

    const operatorBalanceAfter = await ethers.provider.getBalance(attackerOperator.address);

    expect(await vulnerableTreasury.treasuryBalance()).to.equal(0n);
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.equal(0n);
    expect(operatorBalanceAfter).to.equal(
      operatorBalanceBefore + ethers.parseEther("12") - gasUsed
    );

    await expect(cashoutTx)
      .to.emit(attackerContract, "LootWithdrawn")
      .withArgs(attackerOperator.address, anyValue);
  });
});
