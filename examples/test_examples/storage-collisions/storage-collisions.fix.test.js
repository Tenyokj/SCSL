import { expect } from "chai";
import hre from "hardhat";

describe("Storage collision module: safe-slot proxy vault", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deployStorageCollisionFixedFixture() {
    // Create a realistic actor set:
    // proxy admin, logic owner, two honest depositors, and the attacker operator.
    const { ethers } = connection;
    const [proxyAdmin, logicOwner, alice, bob, attackerOperator] = await ethers.getSigners();

    const logicFactory = await ethers.getContractFactory("SafeVaultLogic");
    const logic = await logicFactory.deploy();
    await logic.waitForDeployment();

    const proxyFactory = await ethers.getContractFactory("SafeSlotProxyVault");
    const proxy = await proxyFactory.deploy(await logic.getAddress(), proxyAdmin.address);
    await proxy.waitForDeployment();

    const proxiedLogic = await ethers.getContractAt("SafeVaultLogic", await proxy.getAddress());

    const attackerFactory = await ethers.getContractFactory("StorageCollisionAttacker");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy();
    await attackerContract.waitForDeployment();

    return {
      ethers,
      proxyAdmin,
      logicOwner,
      alice,
      bob,
      attackerOperator,
      logic,
      proxy,
      proxiedLogic,
      attackerContract,
    };
  }

  it("prevents proxy admin takeover because proxy metadata is stored in isolated slots", async function () {
    const { networkHelpers } = connection;
    const { proxyAdmin, logic, proxy, attackerOperator, attackerContract } =
      await networkHelpers.loadFixture(deployStorageCollisionFixedFixture);

    expect(await proxy.admin()).to.equal(proxyAdmin.address);
    expect(await proxy.implementation()).to.equal(await logic.getAddress());

    await expect(
      attackerContract.connect(attackerOperator).attack(await proxy.getAddress())
    ).to.be.revertedWith("Only admin");

    expect(await proxy.admin()).to.equal(proxyAdmin.address);
    expect(await proxy.implementation()).to.equal(await logic.getAddress());
  });

  it("still allows legitimate initialization and normal deposit-withdraw behavior through the proxy", async function () {
    const { networkHelpers } = connection;
    const { ethers, logicOwner, alice, bob, proxy, proxiedLogic } =
      await networkHelpers.loadFixture(deployStorageCollisionFixedFixture);

    await proxiedLogic.connect(logicOwner).initialize(logicOwner.address);

    expect(await proxiedLogic.owner()).to.equal(logicOwner.address);
    expect(await proxiedLogic.initializedVersion()).to.equal(1n);

    await proxiedLogic.connect(alice).deposit({ value: ethers.parseEther("4") });
    await proxiedLogic.connect(bob).deposit({ value: ethers.parseEther("5") });

    expect(await proxiedLogic.balances(alice.address)).to.equal(
      ethers.parseEther("4")
    );
    expect(await proxiedLogic.balances(bob.address)).to.equal(
      ethers.parseEther("5")
    );

    const aliceBalanceBefore = await ethers.provider.getBalance(alice.address);

    const withdrawTx = await proxiedLogic.connect(alice).withdraw(ethers.parseEther("1"));
    const receipt = await withdrawTx.wait();
    const gasUsed = receipt.gasUsed * receipt.gasPrice;

    const aliceBalanceAfter = await ethers.provider.getBalance(alice.address);

    expect(await proxiedLogic.balances(alice.address)).to.equal(
      ethers.parseEther("3")
    );
    expect(await ethers.provider.getBalance(await proxy.getAddress())).to.equal(
      ethers.parseEther("8")
    );
    expect(aliceBalanceAfter).to.equal(
      aliceBalanceBefore + ethers.parseEther("1") - gasUsed
    );
  });
});
