import { expect } from "chai";
import hre from "hardhat";

describe("Library: TrustedPriceOracleConsumer", function () {
  it("reads prices only from a dedicated trusted oracle and lets the owner rotate it", async function () {
    const { ethers } = await hre.network.connect();
    const [owner, nextOracleOwner] = await ethers.getSigners();

    const oracleFactory = await ethers.getContractFactory("MockTrustedPriceOracle");
    const oracle = await oracleFactory.deploy(1_500n);
    await oracle.waitForDeployment();

    const nextOracle = await oracleFactory.connect(nextOracleOwner).deploy(1_750n);
    await nextOracle.waitForDeployment();

    const harnessFactory = await ethers.getContractFactory("TrustedPriceOracleConsumerHarness");
    const harness = await harnessFactory.deploy(owner.address, await oracle.getAddress());
    await harness.waitForDeployment();

    expect(await harness.priceOracle()).to.equal(await oracle.getAddress());
    expect(await harness.readPrice()).to.equal(1_500n);

    await harness.connect(owner).setPriceOracle(await nextOracle.getAddress());
    expect(await harness.priceOracle()).to.equal(await nextOracle.getAddress());
    expect(await harness.readPrice()).to.equal(1_750n);

    await nextOracle.setPrice(0n);
    await expect(harness.readPrice()).to.be.revertedWithCustomError(
      harness,
      "TrustedPriceOracleInvalidValue"
    );
  });
});
