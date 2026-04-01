import { expect } from "chai";
import hre from "hardhat";

describe("Library: TrustedPluginRegistry", function () {
  it("allows delegatecall only into explicitly trusted plugins", async function () {
    const { ethers } = await hre.network.connect();
    const [owner, outsider] = await ethers.getSigners();

    const harnessFactory = await ethers.getContractFactory("TrustedPluginRegistryHarness");
    const harness = await harnessFactory.deploy(owner.address);
    await harness.waitForDeployment();

    const valuePluginFactory = await ethers.getContractFactory("TrustedValuePlugin");
    const valuePlugin = await valuePluginFactory.deploy();
    await valuePlugin.waitForDeployment();

    const revertPluginFactory = await ethers.getContractFactory("RevertingTrustedPlugin");
    const revertPlugin = await revertPluginFactory.deploy();
    await revertPlugin.waitForDeployment();

    const setValueCall = valuePlugin.interface.encodeFunctionData("setStoredValue", [77n]);

    await expect(
      harness.connect(owner).executeTrustedPlugin(await valuePlugin.getAddress(), setValueCall)
    ).to.be.revertedWithCustomError(harness, "TrustedPluginRegistryUntrustedPlugin");

    await harness.connect(owner).setTrustedPlugin(await valuePlugin.getAddress(), true);
    await harness.connect(owner).executeTrustedPlugin(await valuePlugin.getAddress(), setValueCall);

    expect(await harness.storedValue()).to.equal(77n);

    const revertCall = revertPlugin.interface.encodeFunctionData("doRevert");
    await harness.connect(owner).setTrustedPlugin(await revertPlugin.getAddress(), true);

    await expect(
      harness.connect(owner).executeTrustedPlugin(await revertPlugin.getAddress(), revertCall)
    ).to.be.revertedWithCustomError(harness, "TrustedPluginRegistryDelegatecallFailed");

    await expect(
      harness.connect(outsider).setTrustedPlugin(await valuePlugin.getAddress(), true)
    ).to.be.revertedWithCustomError(harness, "OwnableUnauthorizedAccount");
  });
});
