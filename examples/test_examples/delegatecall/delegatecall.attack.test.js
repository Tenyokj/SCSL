import { anyValue } from "@nomicfoundation/hardhat-ethers-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";

describe("Delegatecall module: vulnerable plugin vault", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deployDelegatecallVulnerableFixture() {
    // Create a realistic actor set:
    // owner, two honest depositors, and the attacker operator.
    const { ethers } = connection;
    const [owner, alice, bob, attackerOperator] = await ethers.getSigners();

    const vulnerableFactory = await ethers.getContractFactory("PluginVault");
    const vulnerableVault = await vulnerableFactory.deploy(owner.address);
    await vulnerableVault.waitForDeployment();

    const attackerFactory = await ethers.getContractFactory("DelegatecallHijacker");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy();
    await attackerContract.waitForDeployment();

    // Honest users fund the vault.
    await vulnerableVault.connect(alice).deposit({ value: ethers.parseEther("4") });
    await vulnerableVault.connect(bob).deposit({ value: ethers.parseEther("5") });

    return {
      ethers,
      owner,
      alice,
      bob,
      attackerOperator,
      vulnerableVault,
      attackerContract,
    };
  }

  it("allows an attacker to hijack ownership via delegatecall and drain the vault", async function () {
    const { networkHelpers } = connection;
    const { ethers, owner, vulnerableVault, attackerOperator, attackerContract } =
      await networkHelpers.loadFixture(deployDelegatecallVulnerableFixture);

    expect(await vulnerableVault.owner()).to.equal(owner.address);
    expect(await vulnerableVault.vaultBalance()).to.equal(
      ethers.parseEther("9")
    );

    await expect(
      attackerContract
        .connect(attackerOperator)
        .attack(await vulnerableVault.getAddress())
    )
      .to.emit(attackerContract, "AttackExecuted")
      .withArgs(await vulnerableVault.getAddress(), anyValue);

    expect(await vulnerableVault.owner()).to.equal(
      await attackerContract.getAddress()
    );
    expect(await vulnerableVault.vaultBalance()).to.equal(0n);
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.equal(ethers.parseEther("9"));
  });

  it("lets the attacker operator cash out the stolen Ether after the delegatecall takeover", async function () {
    const { networkHelpers } = connection;
    const { ethers, vulnerableVault, attackerOperator, attackerContract } =
      await networkHelpers.loadFixture(deployDelegatecallVulnerableFixture);

    await attackerContract
      .connect(attackerOperator)
      .attack(await vulnerableVault.getAddress());

    const operatorBalanceBefore = await ethers.provider.getBalance(attackerOperator.address);

    const cashoutTx = await attackerContract
      .connect(attackerOperator)
      .withdrawLoot();
    const receipt = await cashoutTx.wait();
    const gasUsed = receipt.gasUsed * receipt.gasPrice;

    const operatorBalanceAfter = await ethers.provider.getBalance(attackerOperator.address);

    expect(await vulnerableVault.vaultBalance()).to.equal(0n);
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.equal(0n);
    expect(operatorBalanceAfter).to.equal(
      operatorBalanceBefore + ethers.parseEther("9") - gasUsed
    );

    await expect(cashoutTx)
      .to.emit(attackerContract, "LootWithdrawn")
      .withArgs(attackerOperator.address, anyValue);
  });
});
