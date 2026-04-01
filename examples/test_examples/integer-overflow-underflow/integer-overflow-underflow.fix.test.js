import { expect } from "chai";
import hre from "hardhat";

describe("Integer overflow / underflow module: safe reward vault", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deploySafeVaultFixture() {
    // Create a realistic actor set:
    // deployer, two honest depositors, and the attacker operator.
    const { ethers } = connection;
    const [deployer, alice, bob, attackerOperator] = await ethers.getSigners();

    const fixedFactory = await ethers.getContractFactory("SafeRewardVault");
    const fixedVault = await fixedFactory.deploy();
    await fixedVault.waitForDeployment();

    const attackerFactory = await ethers.getContractFactory("UnderflowRewardVaultAttacker");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy(await fixedVault.getAddress());
    await attackerContract.waitForDeployment();

    await fixedVault.connect(alice).deposit({ value: ethers.parseEther("3") });
    await fixedVault.connect(bob).deposit({ value: ethers.parseEther("4") });

    return {
      ethers,
      deployer,
      alice,
      bob,
      attackerOperator,
      fixedVault,
      attackerContract,
    };
  }

  it("rejects the underflow exploit and preserves honest-user funds", async function () {
    const { networkHelpers } = connection;
    const { ethers, alice, bob, attackerOperator, fixedVault, attackerContract } =
      await networkHelpers.loadFixture(deploySafeVaultFixture);

    expect(await fixedVault.vaultBalance()).to.equal(
      ethers.parseEther("7")
    );

    await expect(
      attackerContract.connect(attackerOperator).attack()
    ).to.be.revertedWith("Insufficient credits");

    expect(await fixedVault.vaultBalance()).to.equal(
      ethers.parseEther("7")
    );
    expect(await fixedVault.rewardCredits(alice.address)).to.equal(
      ethers.parseEther("3") * 10n ** 18n
    );
    expect(await fixedVault.rewardCredits(bob.address)).to.equal(
      ethers.parseEther("4") * 10n ** 18n
    );
    expect(
      await fixedVault.rewardCredits(await attackerContract.getAddress())
    ).to.equal(0n);
  });

  it("still allows honest users to redeem their own credits normally", async function () {
    const { networkHelpers } = connection;
    const { ethers, alice, fixedVault } =
      await networkHelpers.loadFixture(deploySafeVaultFixture);

    const aliceCreditsBefore = await fixedVault.rewardCredits(alice.address);
    const aliceBalanceBefore = await ethers.provider.getBalance(alice.address);

    const redeemAmount = ethers.parseEther("1") * 10n ** 18n;
    const redeemTx = await fixedVault.connect(alice).redeem(redeemAmount);
    const receipt = await redeemTx.wait();
    const gasUsed = receipt.gasUsed * receipt.gasPrice;

    const aliceBalanceAfter = await ethers.provider.getBalance(alice.address);

    expect(await fixedVault.vaultBalance()).to.equal(
      ethers.parseEther("6")
    );
    expect(await fixedVault.rewardCredits(alice.address)).to.equal(
      aliceCreditsBefore - redeemAmount
    );
    expect(aliceBalanceAfter).to.equal(
      aliceBalanceBefore + ethers.parseEther("1") - gasUsed
    );
  });
});
