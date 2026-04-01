import { expect } from "chai";
import hre from "hardhat";

describe("Library: NoncedAuthorizations", function () {
  it("consumes nonces monotonically and rejects expired deadlines", async function () {
    const { ethers } = await hre.network.connect();
    const [user] = await ethers.getSigners();

    const factory = await ethers.getContractFactory("NoncedAuthorizationsHarness");
    const harness = await factory.deploy();
    await harness.waitForDeployment();

    expect(await harness.authorizationNonce(user.address)).to.equal(0n);
    expect(await harness.consumeNonce.staticCall(user.address)).to.equal(0n);
    await harness.consumeNonce(user.address);
    expect(await harness.authorizationNonce(user.address)).to.equal(1n);
    expect(await harness.consumeNonce.staticCall(user.address)).to.equal(1n);
    await harness.consumeNonce(user.address);
    expect(await harness.authorizationNonce(user.address)).to.equal(2n);

    const latestBlock = await ethers.provider.getBlock("latest");
    const validDeadline = BigInt(latestBlock.timestamp + 60);
    const expiredDeadline = BigInt(latestBlock.timestamp - 1);

    await harness.requireDeadline(validDeadline);
    await expect(harness.requireDeadline(expiredDeadline)).to.be.revertedWithCustomError(
      harness,
      "AuthorizationExpired"
    );
  });
});
