import { expect } from "chai";
import { getBytes, solidityPackedKeccak256 } from "ethers";
import hre from "hardhat";

describe("Signature replay module: nonced signature vault", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deploySignatureReplayFixedFixture() {
    // Create a realistic actor set:
    // authorized signer, two honest depositors, a claimant, and the attacker operator.
    const { ethers } = connection;
    const [authorizedSigner, alice, bob, claimant, attackerOperator] =
      await ethers.getSigners();

    const fixedFactory = await ethers.getContractFactory("NoncedSignatureVault");
    const fixedVault = await fixedFactory.deploy(authorizedSigner.address);
    await fixedVault.waitForDeployment();

    const attackerFactory = await ethers.getContractFactory("SignatureReplayAttacker");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy(await fixedVault.getAddress());
    await attackerContract.waitForDeployment();

    await fixedVault.connect(alice).deposit({ value: ethers.parseEther("3") });
    await fixedVault.connect(bob).deposit({ value: ethers.parseEther("4") });

    const claimAmount = ethers.parseEther("1");
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

    const claimantMessageHash = solidityPackedKeccak256(
      ["uint256", "address", "address", "uint256", "uint256", "uint256"],
      [
        hre.config.networks.hardhat.chainId,
        await fixedVault.getAddress(),
        claimant.address,
        claimAmount,
        0,
        deadline,
      ]
    );
    const claimantSignature = await authorizedSigner.signMessage(
      getBytes(claimantMessageHash)
    );

    const attackerMessageHash = solidityPackedKeccak256(
      ["uint256", "address", "address", "uint256", "uint256", "uint256"],
      [
        hre.config.networks.hardhat.chainId,
        await fixedVault.getAddress(),
        await attackerContract.getAddress(),
        claimAmount,
        0,
        deadline,
      ]
    );
    const attackerSignature = await authorizedSigner.signMessage(
      getBytes(attackerMessageHash)
    );

    return {
      ethers,
      authorizedSigner,
      alice,
      bob,
      claimant,
      attackerOperator,
      fixedVault,
      attackerContract,
      claimAmount,
      deadline,
      claimantSignature,
      attackerSignature,
    };
  }

  it("rejects replay attempts because each signature is bound to a nonce and consumed after first use", async function () {
    const { networkHelpers } = connection;
    const {
      claimAmount,
      attackerOperator,
      fixedVault,
      attackerContract,
      attackerSignature,
    } = await networkHelpers.loadFixture(deploySignatureReplayFixedFixture);

    let revertError;

    try {
      await attackerContract
        .connect(attackerOperator)
        .attack(claimAmount, attackerSignature, 2);
    } catch (error) {
      revertError = error;
    }

    expect(revertError).to.not.equal(undefined);
    expect(revertError.message).to.include(
      "function selector was not recognized"
    );

    // The generic helper attacker cannot exploit the fixed vault because the function
    // signature no longer matches the vulnerable interface and replay semantics are gone.
    expect(await fixedVault.vaultBalance()).to.equal(7n * 10n ** 18n);
    expect(await fixedVault.nonces(await attackerContract.getAddress())).to.equal(0n);
  });

  it("still allows a legitimate one-time signed claim and prevents reusing the same signature", async function () {
    const { networkHelpers } = connection;
    const {
      ethers,
      claimant,
      fixedVault,
      claimAmount,
      deadline,
      claimantSignature,
    } = await networkHelpers.loadFixture(deploySignatureReplayFixedFixture);

    const claimantBalanceBefore = await ethers.provider.getBalance(claimant.address);

    const claimTx = await fixedVault
      .connect(claimant)
      .claim(claimAmount, deadline, claimantSignature);
    const receipt = await claimTx.wait();
    const gasUsed = receipt.gasUsed * receipt.gasPrice;

    const claimantBalanceAfter = await ethers.provider.getBalance(claimant.address);

    expect(await fixedVault.vaultBalance()).to.equal(
      ethers.parseEther("6")
    );
    expect(await fixedVault.nonces(claimant.address)).to.equal(1n);
    expect(claimantBalanceAfter).to.equal(
      claimantBalanceBefore + claimAmount - gasUsed
    );

    await expect(
      fixedVault.connect(claimant).claim(claimAmount, deadline, claimantSignature)
    ).to.be.revertedWith("Invalid signature");
  });
});
