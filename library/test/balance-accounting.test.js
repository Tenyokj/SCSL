import { expect } from "chai";
import hre from "hardhat";

describe("Library: BalanceAccounting", function () {
  it("credits and debits balances with explicit insufficient-balance protection", async function () {
    const { ethers } = await hre.network.connect();
    const [user] = await ethers.getSigners();

    const factory = await ethers.getContractFactory("BalanceAccountingHarness");
    const harness = await factory.deploy();
    await harness.waitForDeployment();

    expect(await harness.balanceOf(user.address)).to.equal(0n);
    expect(await harness.credit.staticCall(user.address, 5n)).to.equal(5n);
    await harness.credit(user.address, 5n);
    expect(await harness.balanceOf(user.address)).to.equal(5n);

    expect(await harness.debit.staticCall(user.address, 2n)).to.equal(3n);
    await harness.debit(user.address, 2n);
    expect(await harness.balanceOf(user.address)).to.equal(3n);

    await expect(harness.debit(user.address, 4n)).to.be.revertedWithCustomError(
      harness,
      "BalanceAccountingInsufficientBalance"
    );
  });
});
