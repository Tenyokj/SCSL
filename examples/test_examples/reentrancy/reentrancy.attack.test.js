import { anyValue } from "@nomicfoundation/hardhat-ethers-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";

describe("Reentrancy module: vulnerable vault", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deployVulnerableFixture() {
    // Create a realistic actor set:
    // deployer, two honest users, and the attacker operator.
    const { ethers } = connection;
    const [deployer, alice, bob, attackerOperator] = await ethers.getSigners();

    // Deploy the vulnerable vault.
    const vulnerableFactory = await ethers.getContractFactory("VulnerableVault");
    const vulnerableVault = await vulnerableFactory.deploy();
    await vulnerableVault.waitForDeployment();

    // Deploy the attacker contract and point it to the target vault.
    const attackerFactory = await ethers.getContractFactory("ReentrancyAttacker");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy(await vulnerableVault.getAddress());
    await attackerContract.waitForDeployment();

    // Alice and Bob provide honest user liquidity.
    await vulnerableVault
      .connect(alice)
      .deposit({ value: ethers.parseEther("5") });
    await vulnerableVault
      .connect(bob)
      .deposit({ value: ethers.parseEther("5") });

    return {
      deployer,
      alice,
      bob,
      attackerOperator,
      vulnerableVault,
      attackerContract,
    };
  }

  it("allows an attacker to drain funds that belong to other depositors", async function () {
    const { networkHelpers, ethers } = connection;
    const {
      alice,
      bob,
      attackerOperator,
      vulnerableVault,
      attackerContract,
    } = await networkHelpers.loadFixture(deployVulnerableFixture);

    // Confirm the starting state: 10 ETH from honest users sit in the vault.
    expect(await vulnerableVault.vaultBalance()).to.equal(
      ethers.parseEther("10")
    );
    expect(await vulnerableVault.balances(alice.address)).to.equal(
      ethers.parseEther("5")
    );
    expect(await vulnerableVault.balances(bob.address)).to.equal(
      ethers.parseEther("5")
    );

    // The attacker uses only 1 ETH as seed capital to start the exploit.
    const attackValue = ethers.parseEther("1");

    await expect(
      attackerContract.connect(attackerOperator).attack({ value: attackValue })
    )
      .to.emit(attackerContract, "AttackStarted")
      .withArgs(attackValue);

    // After the reentrancy chain, the vault should be completely drained.
    expect(await vulnerableVault.vaultBalance()).to.equal(0n);

    // The attacker contract now holds all 11 ETH:
    // 10 ETH from honest users plus its own 1 ETH seed deposit.
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.equal(ethers.parseEther("11"));

    // Internal accounting still claims the honest users have balances,
    // even though the contract no longer holds enough Ether to honor them.
    expect(await vulnerableVault.balances(alice.address)).to.equal(
      ethers.parseEther("5")
    );
    expect(await vulnerableVault.balances(bob.address)).to.equal(
      ethers.parseEther("5")
    );

    // Because the contract writes a stale memory snapshot back to storage,
    // the attacker's final internal balance looks like zero after the drain.
    expect(
      await vulnerableVault.balances(await attackerContract.getAddress())
    ).to.equal(0n);
  });

  it("lets the attacker cash out the stolen Ether after the vault is drained", async function () {
    const { networkHelpers, ethers } = connection;
    const { attackerOperator, vulnerableVault, attackerContract } =
      await networkHelpers.loadFixture(deployVulnerableFixture);

    await attackerContract
      .connect(attackerOperator)
      .attack({ value: ethers.parseEther("1") });

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
      operatorBalanceBefore + ethers.parseEther("11") - gasUsed
    );

    await expect(cashoutTx)
      .to.emit(attackerContract, "LootWithdrawn")
      .withArgs(attackerOperator.address, anyValue);
  });
});
