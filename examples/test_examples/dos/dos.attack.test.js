import { expect } from "chai";
import hre from "hardhat";

describe("DoS module: push-refund auction", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deployDosVulnerableFixture() {
    // Create a realistic actor set:
    // seller, two honest bidders, one additional challenger, and the attacker operator.
    const { ethers } = connection;
    const [seller, alice, bob, charlie, attackerOperator] =
      await ethers.getSigners();

    const vulnerableFactory = await ethers.getContractFactory("PushRefundAuction");
    const vulnerableAuction = await vulnerableFactory
      .connect(seller)
      .deploy(7 * 24 * 60 * 60);
    await vulnerableAuction.waitForDeployment();

    const attackerFactory = await ethers.getContractFactory("RefundRejectingBidder");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy(await vulnerableAuction.getAddress());
    await attackerContract.waitForDeployment();

    // Honest bidding starts normally.
    await vulnerableAuction.connect(alice).bid({ value: ethers.parseEther("1") });
    await vulnerableAuction.connect(bob).bid({ value: ethers.parseEther("2") });

    return {
      ethers,
      seller,
      alice,
      bob,
      charlie,
      attackerOperator,
      vulnerableAuction,
      attackerContract,
    };
  }

  it("allows a malicious highest bidder to freeze the auction by rejecting refunds", async function () {
    const { networkHelpers } = connection;
    const {
      ethers,
      charlie,
      attackerOperator,
      vulnerableAuction,
      attackerContract,
    } = await networkHelpers.loadFixture(deployDosVulnerableFixture);

    // The attacker becomes the current leader with a contract that rejects future refunds.
    await attackerContract
      .connect(attackerOperator)
      .placeBlockingBid({ value: ethers.parseEther("3") });

    expect(await vulnerableAuction.highestBid()).to.equal(
      ethers.parseEther("3")
    );
    expect(await vulnerableAuction.highestBidder()).to.equal(
      await attackerContract.getAddress()
    );

    // A higher honest bid should succeed in a healthy auction, but here it reverts
    // because the auction tries to refund the attacker inline.
    await expect(
      vulnerableAuction.connect(charlie).bid({ value: ethers.parseEther("4") })
    ).to.be.revertedWith("Refund transfer failed");

    expect(await vulnerableAuction.highestBid()).to.equal(
      ethers.parseEther("3")
    );
    expect(await vulnerableAuction.highestBidder()).to.equal(
      await attackerContract.getAddress()
    );
  });
});
