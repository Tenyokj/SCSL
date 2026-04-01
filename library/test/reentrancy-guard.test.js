import { expect } from "chai";
import hre from "hardhat";

describe("Library: ReentrancyGuard", function () {
  it("blocks nested entry into a protected function", async function () {
    const { ethers } = await hre.network.connect();
    const [deployer] = await ethers.getSigners();

    const harnessFactory = await ethers.getContractFactory("ReentrancyGuardHarness");
    const harness = await harnessFactory.connect(deployer).deploy();
    await harness.waitForDeployment();

    const probeFactory = await ethers.getContractFactory("ReentrancyProbe");
    const probe = await probeFactory.connect(deployer).deploy(await harness.getAddress());
    await probe.waitForDeployment();

    await expect(harness.callProbe(await probe.getAddress())).to.be.revertedWithCustomError(
      harness,
      "ReentrancyGuardReentrantCall"
    );

    expect(await harness.executionCount()).to.equal(0n);
  });
});
