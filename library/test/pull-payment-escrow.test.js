import { expect } from "chai";
import hre from "hardhat";

describe("Library: PullPaymentEscrow", function () {
  it("queues ETH for later withdrawal instead of forcing a push payment", async function () {
    const { ethers } = await hre.network.connect();
    const [sender, recipient] = await ethers.getSigners();

    const factory = await ethers.getContractFactory("PullPaymentEscrowHarness");
    const harness = await factory.connect(sender).deploy();
    await harness.waitForDeployment();

    await harness.connect(sender).queuePayment(recipient.address, {
      value: ethers.parseEther("1"),
    });

    expect(await harness.payments(recipient.address)).to.equal(ethers.parseEther("1"));

    const balanceBefore = await ethers.provider.getBalance(recipient.address);
    const tx = await harness.connect(recipient).withdrawMyPayment();
    const receipt = await tx.wait();
    const gasUsed = receipt.gasUsed * receipt.gasPrice;
    const balanceAfter = await ethers.provider.getBalance(recipient.address);

    expect(await harness.payments(recipient.address)).to.equal(0n);
    expect(balanceAfter).to.equal(balanceBefore + ethers.parseEther("1") - gasUsed);
  });
});
