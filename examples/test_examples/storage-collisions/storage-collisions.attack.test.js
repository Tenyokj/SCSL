import { anyValue } from "@nomicfoundation/hardhat-ethers-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";

describe("Storage collision module: vulnerable proxy vault", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deployStorageCollisionVulnerableFixture() {
    // Create a realistic actor set:
    // proxy admin, two honest depositors, and the attacker operator.
    const { ethers } = connection;
    const [proxyAdmin, alice, bob, attackerOperator] = await ethers.getSigners();

    const logicFactory = await ethers.getContractFactory("CollidingVaultLogic");
    const logic = await logicFactory.deploy();
    await logic.waitForDeployment();

    const proxyFactory = await ethers.getContractFactory("CollidingProxyVault");
    const proxy = await proxyFactory.deploy(await logic.getAddress(), proxyAdmin.address);
    await proxy.waitForDeployment();

    const proxiedLogic = await ethers.getContractAt("CollidingVaultLogic", await proxy.getAddress());

    // Honest users deposit Ether into the proxied vault before anyone notices the initialization issue.
    await proxiedLogic.connect(alice).deposit({ value: ethers.parseEther("4") });
    await proxiedLogic.connect(bob).deposit({ value: ethers.parseEther("5") });

    const attackerFactory = await ethers.getContractFactory("StorageCollisionAttacker");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy();
    await attackerContract.waitForDeployment();

    return {
      ethers,
      proxyAdmin,
      alice,
      bob,
      attackerOperator,
      logic,
      proxy,
      proxiedLogic,
      attackerContract,
    };
  }

  it("lets an attacker become proxy admin through delegatecall storage collision and drain the vault", async function () {
    const { networkHelpers } = connection;
    const { ethers, proxyAdmin, logic, proxy, attackerOperator, attackerContract } =
      await networkHelpers.loadFixture(deployStorageCollisionVulnerableFixture);

    expect(await proxy.admin()).to.equal(proxyAdmin.address);
    expect(await proxy.implementation()).to.equal(await logic.getAddress());
    expect(await ethers.provider.getBalance(await proxy.getAddress())).to.equal(
      ethers.parseEther("9")
    );

    await expect(
      attackerContract.connect(attackerOperator).attack(await proxy.getAddress())
    )
      .to.emit(attackerContract, "AttackExecuted")
      .withArgs(await proxy.getAddress(), anyValue);

    expect(await proxy.admin()).to.equal(await attackerContract.getAddress());
    expect(await proxy.implementation()).to.equal(await logic.getAddress());
    expect(await ethers.provider.getBalance(await proxy.getAddress())).to.equal(0n);
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.equal(ethers.parseEther("9"));
  });

  it("lets the attacker operator cash out the ETH stolen through the storage-collision takeover", async function () {
    const { networkHelpers } = connection;
    const { ethers, proxy, attackerOperator, attackerContract } =
      await networkHelpers.loadFixture(deployStorageCollisionVulnerableFixture);

    await attackerContract.connect(attackerOperator).attack(await proxy.getAddress());

    const operatorBalanceBefore = await ethers.provider.getBalance(attackerOperator.address);

    const cashoutTx = await attackerContract
      .connect(attackerOperator)
      .withdrawLoot();
    const receipt = await cashoutTx.wait();
    const gasUsed = receipt.gasUsed * receipt.gasPrice;

    const operatorBalanceAfter = await ethers.provider.getBalance(attackerOperator.address);

    expect(await ethers.provider.getBalance(await proxy.getAddress())).to.equal(0n);
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.equal(0n);
    expect(operatorBalanceAfter).to.equal(
      operatorBalanceBefore + ethers.parseEther("9") - gasUsed
    );
  });
});
