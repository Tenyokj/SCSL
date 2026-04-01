import { expect } from "chai";
import hre from "hardhat";

describe("Library: NativeTransfer", function () {
  it("forwards ETH with explicit recipient and amount validation", async function () {
    const { ethers } = await hre.network.connect();
    const [sender, recipient] = await ethers.getSigners();

    const factory = await ethers.getContractFactory("NativeTransferHarness");
    const harness = await factory.connect(sender).deploy();
    await harness.waitForDeployment();

    const balanceBefore = await ethers.provider.getBalance(recipient.address);
    await harness.connect(sender).forward(recipient.address, {
      value: ethers.parseEther("0.25"),
    });
    const balanceAfter = await ethers.provider.getBalance(recipient.address);

    expect(balanceAfter - balanceBefore).to.equal(ethers.parseEther("0.25"));

    await expect(
      harness.connect(sender).forward(ethers.ZeroAddress, { value: 1n })
    ).to.be.revertedWithCustomError(harness, "NativeTransferInvalidRecipient");
  });
});
