import { expect } from "chai";
import hre from "hardhat";

describe("Library: TwoStepOwnable", function () {
  it("requires the pending owner to explicitly accept ownership", async function () {
    const { ethers } = await hre.network.connect();
    const [owner, nextOwner] = await ethers.getSigners();

    const factory = await ethers.getContractFactory("TwoStepOwnableHarness");
    const harness = await factory.deploy(owner.address);
    await harness.waitForDeployment();

    await harness.connect(owner).transferOwnership(nextOwner.address);
    expect(await harness.owner()).to.equal(owner.address);
    expect(await harness.pendingOwnership()).to.equal(nextOwner.address);

    await expect(harness.connect(nextOwner).acceptOwnership())
      .to.emit(harness, "OwnershipTransferred")
      .withArgs(owner.address, nextOwner.address);

    expect(await harness.owner()).to.equal(nextOwner.address);
    expect(await harness.pendingOwnership()).to.equal(ethers.ZeroAddress);
  });
});
