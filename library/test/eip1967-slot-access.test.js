import { expect } from "chai";
import hre from "hardhat";

describe("Library: EIP1967SlotAccess", function () {
  it("reads and writes admin and implementation through isolated EIP-1967 slots", async function () {
    const { ethers } = await hre.network.connect();
    const [admin, implementation] = await ethers.getSigners();

    const factory = await ethers.getContractFactory("EIP1967SlotAccessHarness");
    const harness = await factory.deploy();
    await harness.waitForDeployment();

    await harness.setAdmin(admin.address);
    await harness.setImplementation(implementation.address);

    expect(await harness.admin()).to.equal(admin.address);
    expect(await harness.implementation()).to.equal(implementation.address);

    await expect(harness.setAdmin(ethers.ZeroAddress)).to.be.revertedWithCustomError(
      harness,
      "EIP1967InvalidAdmin"
    );
    await expect(harness.setImplementation(ethers.ZeroAddress)).to.be.revertedWithCustomError(
      harness,
      "EIP1967InvalidImplementation"
    );
  });
});
