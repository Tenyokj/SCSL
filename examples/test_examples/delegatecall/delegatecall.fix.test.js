import { expect } from "chai";
import hre from "hardhat";

describe("Delegatecall module: trusted plugin vault", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deployDelegatecallFixedFixture() {
    // Create a realistic actor set:
    // owner, two honest depositors, and the attacker operator.
    const { ethers } = connection;
    const [owner, alice, bob, attackerOperator, coldWallet] =
      await ethers.getSigners();

    const fixedFactory = await ethers.getContractFactory("TrustedPluginVault");
    const fixedVault = await fixedFactory.deploy(owner.address);
    await fixedVault.waitForDeployment();

    const safePluginFactory = await ethers.getContractFactory("SafeCounterPlugin");
    const safePlugin = await safePluginFactory.deploy();
    await safePlugin.waitForDeployment();

    const attackerFactory = await ethers.getContractFactory("DelegatecallHijacker");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy();
    await attackerContract.waitForDeployment();

    await fixedVault.connect(alice).deposit({ value: ethers.parseEther("4") });
    await fixedVault.connect(bob).deposit({ value: ethers.parseEther("5") });

    return {
      ethers,
      owner,
      alice,
      bob,
      attackerOperator,
      coldWallet,
      fixedVault,
      safePlugin,
      attackerContract,
    };
  }

  it("blocks arbitrary delegatecall takeover attempts and preserves vault funds", async function () {
    const { networkHelpers } = connection;
    const { ethers, owner, attackerOperator, fixedVault, attackerContract } =
      await networkHelpers.loadFixture(deployDelegatecallFixedFixture);

    expect(await fixedVault.owner()).to.equal(owner.address);
    expect(await fixedVault.vaultBalance()).to.equal(
      ethers.parseEther("9")
    );

    await expect(
      attackerContract
        .connect(attackerOperator)
        .attack(await fixedVault.getAddress())
    ).to.be.revertedWith("Only owner");

    expect(await fixedVault.owner()).to.equal(owner.address);
    expect(await fixedVault.vaultBalance()).to.equal(
      ethers.parseEther("9")
    );
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.equal(0n);
  });

  it("still allows legitimate trusted plugin execution by the owner", async function () {
    const { networkHelpers } = connection;
    const { owner, coldWallet, fixedVault, safePlugin } =
      await networkHelpers.loadFixture(deployDelegatecallFixedFixture);

    await fixedVault
      .connect(owner)
      .setTrustedPlugin(await safePlugin.getAddress(), true);

    await fixedVault
      .connect(owner)
      .runPlugin(
        await safePlugin.getAddress(),
        safePlugin.interface.encodeFunctionData("incrementExecutionCount")
      );

    expect(await fixedVault.pluginExecutionCount()).to.equal(1n);

    const sweepTx = await fixedVault.connect(owner).sweepFunds(coldWallet.address);
    await sweepTx.wait();

    expect(await fixedVault.vaultBalance()).to.equal(0n);
  });
});
