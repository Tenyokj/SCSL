import { expect } from "chai";
import hre from "hardhat";

describe("Library: ExecutionConstraints", function () {
  it("enforces deadlines and minimum output constraints", async function () {
    const { ethers } = await hre.network.connect();

    const factory = await ethers.getContractFactory("ExecutionConstraintsHarness");
    const harness = await factory.deploy();
    await harness.waitForDeployment();

    const latestBlock = await ethers.provider.getBlock("latest");
    const validDeadline = BigInt(latestBlock.timestamp + 120);
    const expiredDeadline = BigInt(latestBlock.timestamp - 1);

    await harness.enforceDeadline(validDeadline);
    await expect(harness.enforceDeadline(expiredDeadline)).to.be.revertedWithCustomError(
      harness,
      "ExecutionDeadlineExpired"
    );

    await harness.enforceMinimumOutput(100n, 95n);
    await expect(harness.enforceMinimumOutput(90n, 95n)).to.be.revertedWithCustomError(
      harness,
      "ExecutionInsufficientOutput"
    );
  });
});
