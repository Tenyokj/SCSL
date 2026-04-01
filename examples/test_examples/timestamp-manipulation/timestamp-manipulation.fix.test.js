import { expect } from "chai";
import hre from "hardhat";

describe("Timestamp manipulation module: block-based last-buyer game", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deployTimestampFixedFixture() {
    // Create a realistic actor set:
    // two honest users and the attacker operator.
    const { ethers } = connection;
    const [deployer, alice, bob, attackerOperator] = await ethers.getSigners();

    const fixedFactory = await ethers.getContractFactory("BlockBasedLastBuyerGame");
    const fixedGame = await fixedFactory.deploy(300);
    await fixedGame.waitForDeployment();

    const attackerFactory = await ethers.getContractFactory("TimestampBoundaryAttacker");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy(await fixedGame.getAddress());
    await attackerContract.waitForDeployment();

    await fixedGame.connect(alice).buyIn({ value: ethers.parseEther("2") });
    await fixedGame.connect(bob).buyIn({ value: ethers.parseEther("3") });
    await attackerContract
      .connect(attackerOperator)
      .becomeLastBuyer({ value: ethers.parseEther("1") });

    return {
      ethers,
      deployer,
      alice,
      bob,
      attackerOperator,
      fixedGame,
      attackerContract,
    };
  }

  it("does not let timestamp skew bypass a block-based cooldown", async function () {
    const { networkHelpers } = connection;
    const { ethers, attackerOperator, fixedGame, attackerContract } =
      await networkHelpers.loadFixture(deployTimestampFixedFixture);

    expect(await fixedGame.potBalance()).to.equal(
      ethers.parseEther("6")
    );

    const lastBuyBlock = await ethers.provider.getBlockNumber();

    // Even if a validator chooses a far-future timestamp for the next block,
    // the cooldown still depends on block.number and therefore remains unfulfilled.
    await networkHelpers.time.increase(3590);
    await networkHelpers.time.setNextBlockTimestamp(
      (await networkHelpers.time.latest()) + 1000
    );

    await expect(
      attackerContract.connect(attackerOperator).claimPot()
    ).to.be.revertedWith("Cooldown not finished");

    expect(await fixedGame.lastBuyBlock()).to.equal(BigInt(lastBuyBlock));
    expect(await fixedGame.potBalance()).to.equal(
      ethers.parseEther("6")
    );
  });

  it("still allows the last buyer to claim legitimately after enough blocks have passed", async function () {
    const { networkHelpers } = connection;
    const { ethers, attackerOperator, fixedGame, attackerContract } =
      await networkHelpers.loadFixture(deployTimestampFixedFixture);

    await networkHelpers.mine(300);

    await attackerContract.connect(attackerOperator).claimPot();

    expect(await fixedGame.potBalance()).to.equal(0n);
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.equal(ethers.parseEther("6"));
  });
});
