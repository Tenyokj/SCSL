import { expect } from "chai";
import hre from "hardhat";

describe("Front-running / MEV module: slippage-protected AMM", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deployFrontRunningFixedFixture() {
    // Create a realistic actor set:
    // liquidity provider, victim trader, and the attacker operator.
    const { ethers } = connection;
    const [liquidityProvider, victim, attackerOperator] = await ethers.getSigners();

    const tokenFactory = await ethers.getContractFactory("SafeFrontRunToken");
    const token = await tokenFactory.deploy();
    await token.waitForDeployment();

    const ammFactory = await ethers.getContractFactory("SlippageProtectedETHToTokenAMM");
    const fixedAmm = await ammFactory.deploy(await token.getAddress());
    await fixedAmm.waitForDeployment();

    const attackerFactory = await ethers.getContractFactory("FrontrunPriceMover");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy(await fixedAmm.getAddress());
    await attackerContract.waitForDeployment();

    await token.mint(liquidityProvider.address, ethers.parseEther("1000"));
    await token
      .connect(liquidityProvider)
      .approve(await fixedAmm.getAddress(), ethers.parseEther("1000"));
    await fixedAmm
      .connect(liquidityProvider)
      .addLiquidity(ethers.parseEther("1000"), { value: ethers.parseEther("100") });

    return {
      ethers,
      liquidityProvider,
      victim,
      attackerOperator,
      token,
      fixedAmm,
      attackerContract,
    };
  }

  it("reverts the victim swap if frontrunning pushes output below the user-declared minimum", async function () {
    const { networkHelpers } = connection;
    const {
      ethers,
      victim,
      attackerOperator,
      fixedAmm,
      attackerContract,
    } = await networkHelpers.loadFixture(deployFrontRunningFixedFixture);

    const victimExpectedOut = await fixedAmm
      .connect(victim)
      .getTokenAmountOut(ethers.parseEther("10"));
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

    await attackerContract
      .connect(attackerOperator)
      .frontrunBuyWithBounds(0n, deadline, { value: ethers.parseEther("20") });

    await expect(
      fixedAmm
        .connect(victim)
        .swapExactETHForTokens(victimExpectedOut, deadline, {
          value: ethers.parseEther("10"),
        })
    ).to.be.revertedWith("Slippage exceeded");
  });

  it("still allows a legitimate swap when the quote remains within the user's declared bounds", async function () {
    const { networkHelpers } = connection;
    const { ethers, victim, token, fixedAmm } =
      await networkHelpers.loadFixture(deployFrontRunningFixedFixture);

    const minTokensOut = await fixedAmm
      .connect(victim)
      .getTokenAmountOut(ethers.parseEther("10"));
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

    const victimBalanceBefore = await token.balanceOf(victim.address);
    await fixedAmm
      .connect(victim)
      .swapExactETHForTokens(minTokensOut, deadline, { value: ethers.parseEther("10") });
    const victimBalanceAfter = await token.balanceOf(victim.address);

    expect(victimBalanceAfter - victimBalanceBefore).to.equal(minTokensOut);
  });
});
