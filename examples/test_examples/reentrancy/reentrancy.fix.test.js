import { expect } from "chai";
import hre from "hardhat";

describe("Reentrancy module: fixed vault", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deployFixedFixture() {
    // Deploy the secure vault and a realistic set of participants.
    const { ethers } = connection;
    const [deployer, alice, bob, attackerOperator] = await ethers.getSigners();

    const fixedFactory = await ethers.getContractFactory("FixedVault");
    const fixedVault = await fixedFactory.deploy();
    await fixedVault.waitForDeployment();

    const attackerFactory = await ethers.getContractFactory("ReentrancyAttacker");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy(await fixedVault.getAddress());
    await attackerContract.waitForDeployment();

    // Honest users create a shared liquidity pool.
    await fixedVault.connect(alice).deposit({ value: ethers.parseEther("5") });
    await fixedVault.connect(bob).deposit({ value: ethers.parseEther("5") });

    return {
      deployer,
      alice,
      bob,
      attackerOperator,
      fixedVault,
      attackerContract,
    };
  }

  it("blocks reentrancy and preserves the funds of honest users", async function () {
    const { networkHelpers, ethers } = connection;
    const { alice, bob, attackerOperator, fixedVault, attackerContract } =
      await networkHelpers.loadFixture(deployFixedFixture);

    expect(await fixedVault.vaultBalance()).to.equal(
      ethers.parseEther("10")
    );

    // The attack must revert because the fixed vault updates state first
    // and also blocks reentry with a guard.
    await expect(
      attackerContract
        .connect(attackerOperator)
        .attack({ value: ethers.parseEther("1") })
    ).to.be.revertedWith("Ether transfer failed");

    // Because the full transaction reverts, the vault balance does not change.
    expect(await fixedVault.vaultBalance()).to.equal(
      ethers.parseEther("10")
    );

    // Honest-user balances remain intact.
    expect(await fixedVault.balances(alice.address)).to.equal(
      ethers.parseEther("5")
    );
    expect(await fixedVault.balances(bob.address)).to.equal(
      ethers.parseEther("5")
    );

    // The attacker could not create a lasting balance or retain Ether in the exploit contract.
    expect(
      await fixedVault.balances(await attackerContract.getAddress())
    ).to.equal(0n);
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.equal(0n);
  });

  it("still allows honest users to withdraw their funds normally", async function () {
    const { networkHelpers, ethers } = connection;
    const { alice, bob, fixedVault } = await networkHelpers.loadFixture(deployFixedFixture);

    // Alice can still withdraw funds normally.
    const withdrawTx = await fixedVault
      .connect(alice)
      .withdraw(ethers.parseEther("2"));
    await withdrawTx.wait();

    expect(await fixedVault.balances(alice.address)).to.equal(
      ethers.parseEther("3")
    );
    expect(await fixedVault.balances(bob.address)).to.equal(
      ethers.parseEther("5")
    );
    expect(await fixedVault.vaultBalance()).to.equal(
      ethers.parseEther("8")
    );
  });
});
