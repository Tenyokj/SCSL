import { expect } from "chai";
import hre from "hardhat";

describe("Library: BlockCooldown", function () {
  it("uses block-number-based cooldowns instead of timestamp-sensitive delays", async function () {
    const connection = await hre.network.connect();
    const { ethers, networkHelpers } = connection;

    const factory = await ethers.getContractFactory("BlockCooldownHarness");
    const harness = await factory.deploy();
    await harness.waitForDeployment();

    await expect(harness.arm(0n)).to.be.revertedWithCustomError(
      harness,
      "BlockCooldownInvalidLength"
    );

    await harness.arm(3n);
    const unlockBlock = await harness.unlockBlock();

    await expect(harness.executeWhenReady()).to.be.revertedWithCustomError(
      harness,
      "BlockCooldownNotReady"
    );

    await networkHelpers.mine(3);

    expect(await harness.unlockBlock()).to.equal(unlockBlock);
    await harness.executeWhenReady();
  });
});
