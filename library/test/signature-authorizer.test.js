import { expect } from "chai";
import { getBytes, keccak256, toUtf8Bytes } from "ethers";
import hre from "hardhat";

describe("Library: SignatureAuthorizer", function () {
  it("recovers and validates Ethereum signed message signers", async function () {
    const { ethers } = await hre.network.connect();
    const [signer, otherAccount] = await ethers.getSigners();

    const factory = await ethers.getContractFactory("SignatureAuthorizerHarness");
    const harness = await factory.deploy();
    await harness.waitForDeployment();

    const messageHash = keccak256(toUtf8Bytes("SCSL signature authorizer test"));
    const digest = await harness.toEthSignedMessageHash(messageHash);
    const signature = await signer.signMessage(getBytes(messageHash));

    expect(await harness.recoverSigner(digest, signature)).to.equal(signer.address);
    expect(await harness.isAuthorizedSigner(digest, signature, signer.address)).to.equal(true);
    expect(await harness.isAuthorizedSigner(digest, signature, otherAccount.address)).to.equal(false);
  });
});
