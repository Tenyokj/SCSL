import { anyValue } from "@nomicfoundation/hardhat-ethers-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";

describe("Integer overflow / underflow module: unchecked reward vault", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deployUncheckedVaultFixture() {
    // Create a realistic actor set:
    // deployer, two honest depositors, and the attacker operator.
    const { ethers } = connection;
    const [deployer, alice, bob, attackerOperator] = await ethers.getSigners();

    const vulnerableFactory = await ethers.getContractFactory("UncheckedRewardVault");
    const vulnerableVault = await vulnerableFactory.deploy();
    await vulnerableVault.waitForDeployment();

    const attackerFactory = await ethers.getContractFactory("UnderflowRewardVaultAttacker");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy(await vulnerableVault.getAddress());
    await attackerContract.waitForDeployment();

    // Honest users seed the vault with real Ether liquidity.
    await vulnerableVault.connect(alice).deposit({ value: ethers.parseEther("3") });
    await vulnerableVault.connect(bob).deposit({ value: ethers.parseEther("4") });

    return {
      ethers,
      deployer,
      alice,
      bob,
      attackerOperator,
      vulnerableVault,
      attackerContract,
    };
  }

  it("lets an attacker drain the full vault by triggering unchecked underflow in credit accounting", async function () {
    const { networkHelpers } = connection;
    const { ethers, alice, bob, vulnerableVault, attackerContract, attackerOperator } =
      await networkHelpers.loadFixture(deployUncheckedVaultFixture);

    expect(await vulnerableVault.vaultBalance()).to.equal(
      ethers.parseEther("7")
    );
    expect(await vulnerableVault.rewardCredits(alice.address)).to.equal(
      ethers.parseEther("3") * 10n ** 18n
    );
    expect(await vulnerableVault.rewardCredits(bob.address)).to.equal(
      ethers.parseEther("4") * 10n ** 18n
    );
    expect(
      await vulnerableVault.rewardCredits(await attackerContract.getAddress())
    ).to.equal(0n);

    await expect(attackerContract.connect(attackerOperator).attack())
      .to.emit(attackerContract, "AttackExecuted")
      .withArgs(ethers.parseEther("7"), anyValue);

    expect(await vulnerableVault.vaultBalance()).to.equal(0n);
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.equal(ethers.parseEther("7"));

    // Honest users still appear solvent in internal accounting, even though the Ether is gone.
    expect(await vulnerableVault.rewardCredits(alice.address)).to.equal(
      ethers.parseEther("3") * 10n ** 18n
    );
    expect(await vulnerableVault.rewardCredits(bob.address)).to.equal(
      ethers.parseEther("4") * 10n ** 18n
    );

    // The attacker's credits wrapped to a massive uint256 value after underflow.
    expect(
      await vulnerableVault.rewardCredits(await attackerContract.getAddress())
    ).to.be.gt(0n);
  });

  it("lets the attacker operator cash out the stolen Ether after the vault is drained", async function () {
    const { networkHelpers } = connection;
    const { ethers, attackerOperator, vulnerableVault, attackerContract } =
      await networkHelpers.loadFixture(deployUncheckedVaultFixture);

    await attackerContract.connect(attackerOperator).attack();

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
      operatorBalanceBefore + ethers.parseEther("7") - gasUsed
    );

    await expect(cashoutTx)
      .to.emit(attackerContract, "LootWithdrawn")
      .withArgs(attackerOperator.address, anyValue);
  });
});
