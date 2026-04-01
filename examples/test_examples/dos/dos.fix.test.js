import { expect } from "chai";
import hre from "hardhat";

describe("DoS module: pull-refund auction", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deployDosFixedFixture() {
    // Create a realistic actor set:
    // seller, two honest bidders, one challenger, and the attacker operator.
    const { ethers } = connection;
    const [seller, alice, bob, charlie, attackerOperator] =
      await ethers.getSigners();

    const fixedFactory = await ethers.getContractFactory("PullRefundAuction");
    const fixedAuction = await fixedFactory
      .connect(seller)
      .deploy(7 * 24 * 60 * 60);
    await fixedAuction.waitForDeployment();

    const attackerFactory = await ethers.getContractFactory("RefundRejectingBidder");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy(await fixedAuction.getAddress());
    await attackerContract.waitForDeployment();

    await fixedAuction.connect(alice).bid({ value: ethers.parseEther("1") });
    await fixedAuction.connect(bob).bid({ value: ethers.parseEther("2") });

    return {
      ethers,
      seller,
      alice,
      bob,
      charlie,
      attackerOperator,
      fixedAuction,
      attackerContract,
    };
  }

  it("prevents a refund-rejecting bidder from blocking future bids", async function () {
    const { networkHelpers } = connection;
    const {
      ethers,
      charlie,
      attackerOperator,
      fixedAuction,
      attackerContract,
    } = await networkHelpers.loadFixture(deployDosFixedFixture);

    await attackerContract
      .connect(attackerOperator)
      .placeBlockingBid({ value: ethers.parseEther("3") });

    // The honest challenger can still outbid the malicious contract because refunds are queued.
    await fixedAuction.connect(charlie).bid({ value: ethers.parseEther("4") });

    expect(await fixedAuction.highestBid()).to.equal(
      ethers.parseEther("4")
    );
    expect(await fixedAuction.highestBidder()).to.equal(charlie.address);
    expect(
      await fixedAuction.pendingReturns(await attackerContract.getAddress())
    ).to.equal(ethers.parseEther("3"));
  });

  it("still allows queued refunds to be claimed later when the recipient chooses to accept Ether", async function () {
    const { networkHelpers } = connection;
    const {
      ethers,
      charlie,
      attackerOperator,
      fixedAuction,
      attackerContract,
    } = await networkHelpers.loadFixture(deployDosFixedFixture);

    await attackerContract
      .connect(attackerOperator)
      .placeBlockingBid({ value: ethers.parseEther("3") });
    await fixedAuction.connect(charlie).bid({ value: ethers.parseEther("4") });

    // The attacker contract can later choose to accept Ether and withdraw the queued refund.
    await attackerContract.connect(attackerOperator).disableRefundBlock();
    await attackerContract
      .connect(attackerOperator)
      .claimRefund(await fixedAuction.getAddress());

    expect(
      await fixedAuction.pendingReturns(await attackerContract.getAddress())
    ).to.equal(0n);
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.equal(ethers.parseEther("3"));
  });
});
