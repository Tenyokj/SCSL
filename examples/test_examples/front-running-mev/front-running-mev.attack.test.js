import { expect } from "chai";
import hre from "hardhat";

describe("Front-running / MEV module: vulnerable AMM", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deployFrontRunningVulnerableFixture() {
    // Create a realistic actor set:
    // liquidity provider, victim trader, and the attacker operator.
    const { ethers } = connection;
    const [liquidityProvider, victim, attackerOperator] = await ethers.getSigners();

    const tokenFactory = await ethers.getContractFactory("MockFrontRunToken");
    const token = await tokenFactory.deploy();
    await token.waitForDeployment();

    const ammFactory = await ethers.getContractFactory("VulnerableETHToTokenAMM");
    const vulnerableAmm = await ammFactory.deploy(await token.getAddress());
    await vulnerableAmm.waitForDeployment();

    const attackerFactory = await ethers.getContractFactory("FrontrunPriceMover");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy(await vulnerableAmm.getAddress());
    await attackerContract.waitForDeployment();

    // Seed the pool with balanced liquidity.
    await token.mint(liquidityProvider.address, ethers.parseEther("1000"));
    await token
      .connect(liquidityProvider)
      .approve(await vulnerableAmm.getAddress(), ethers.parseEther("1000"));
    await vulnerableAmm
      .connect(liquidityProvider)
      .addLiquidity(ethers.parseEther("1000"), { value: ethers.parseEther("100") });

    return {
      ethers,
      liquidityProvider,
      victim,
      attackerOperator,
      token,
      vulnerableAmm,
      attackerContract,
    };
  }

  it("lets a frontrunner worsen execution price before a victim swap because no minOut is enforced", async function () {
    const { networkHelpers } = connection;
    const {
      ethers,
      victim,
      attackerOperator,
      token,
      vulnerableAmm,
      attackerContract,
    } = await networkHelpers.loadFixture(deployFrontRunningVulnerableFixture);

    // Victim observes the quote before the attacker moves the market.
    const victimExpectedOut = await vulnerableAmm
      .connect(victim)
      .getTokenAmountOut(ethers.parseEther("10"));

    // Attacker buys first and consumes token-side liquidity, making the victim's price worse.
    await attackerContract
      .connect(attackerOperator)
      .frontrunBuy({ value: ethers.parseEther("20") });

    const victimBalanceBefore = await token.balanceOf(victim.address);
    await vulnerableAmm.connect(victim).swapExactETHForTokens({ value: ethers.parseEther("10") });
    const victimBalanceAfter = await token.balanceOf(victim.address);

    const victimActualOut = victimBalanceAfter - victimBalanceBefore;

    expect(victimActualOut).to.be.lt(victimExpectedOut);
    expect(await token.balanceOf(await attackerContract.getAddress())).to.be.gt(0n);
  });
});
