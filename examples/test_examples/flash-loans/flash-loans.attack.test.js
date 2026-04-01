import { anyValue } from "@nomicfoundation/hardhat-ethers-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";

describe("Flash loan module: spot-oracle lending vault", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deployFlashLoanVulnerableFixture() {
    // Create a realistic actor set:
    // AMM liquidity provider, lending-liquidity provider, and the attacker operator.
    const { ethers } = connection;
    const [ammLiquidityProvider, lendingLiquidityProvider, attackerOperator] =
      await ethers.getSigners();

    const tokenFactory = await ethers.getContractFactory("FlashLoanLabToken");
    const token = await tokenFactory.deploy();
    await token.waitForDeployment();

    const lenderFactory = await ethers.getContractFactory("FlashLoanEtherLender");
    const lender = await lenderFactory.deploy({ value: ethers.parseEther("120") });
    await lender.waitForDeployment();

    const ammFactory = await ethers.getContractFactory("FlashLoanSpotAMM");
    const amm = await ammFactory.deploy(await token.getAddress());
    await amm.waitForDeployment();

    const vulnerableVaultFactory = await ethers.getContractFactory("SpotOracleLendingVault");
    const vulnerableVault = await vulnerableVaultFactory.deploy(
      await token.getAddress(),
      await amm.getAddress()
    );
    await vulnerableVault.waitForDeployment();

    const attackerFactory = await ethers.getContractFactory("FlashLoanPriceManipulationAttacker");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy(
        await lender.getAddress(),
        await amm.getAddress(),
        await token.getAddress(),
        await vulnerableVault.getAddress()
      );
    await attackerContract.waitForDeployment();

    // Seed the AMM with shallow liquidity so the spot price is easy to manipulate.
    await token.mint(ammLiquidityProvider.address, ethers.parseEther("1000"));
    await token
      .connect(ammLiquidityProvider)
      .approve(await amm.getAddress(), ethers.parseEther("1000"));
    await amm
      .connect(ammLiquidityProvider)
      .addLiquidity(ethers.parseEther("1000"), { value: ethers.parseEther("100") });

    // Seed the lending vault with ETH liquidity.
    await vulnerableVault
      .connect(lendingLiquidityProvider)
      .supplyLiquidity({ value: ethers.parseEther("150") });

    return {
      ethers,
      ammLiquidityProvider,
      lendingLiquidityProvider,
      attackerOperator,
      token,
      lender,
      amm,
      vulnerableVault,
      attackerContract,
    };
  }

  it("lets an attacker use a flash loan to manipulate AMM spot price and overborrow ETH", async function () {
    const { networkHelpers } = connection;
    const { ethers, lender, vulnerableVault, attackerOperator, attackerContract } =
      await networkHelpers.loadFixture(deployFlashLoanVulnerableFixture);

    expect(await vulnerableVault.vaultBalance()).to.equal(
      ethers.parseEther("150")
    );
    expect(await ethers.provider.getBalance(await lender.getAddress())).to.equal(
      ethers.parseEther("120")
    );

    await expect(
      attackerContract.connect(attackerOperator).attack(ethers.parseEther("80"))
    )
      .to.emit(attackerContract, "AttackExecuted")
      .withArgs(ethers.parseEther("80"), anyValue, anyValue);

    // The flash lender is fully repaid, but the lending vault has been drained significantly.
    expect(await ethers.provider.getBalance(await lender.getAddress())).to.equal(
      ethers.parseEther("120")
    );
    expect(await vulnerableVault.vaultBalance()).to.be.lt(ethers.parseEther("43"));
    expect(await vulnerableVault.vaultBalance()).to.be.gt(ethers.parseEther("41"));
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.be.gt(ethers.parseEther("27"));
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.be.lt(ethers.parseEther("29"));
  });

  it("lets the attacker operator cash out the ETH stolen through flash-loan price manipulation", async function () {
    const { networkHelpers } = connection;
    const { ethers, vulnerableVault, attackerOperator, attackerContract } =
      await networkHelpers.loadFixture(deployFlashLoanVulnerableFixture);

    await attackerContract.connect(attackerOperator).attack(ethers.parseEther("80"));

    const operatorBalanceBefore = await ethers.provider.getBalance(attackerOperator.address);

    const cashoutTx = await attackerContract
      .connect(attackerOperator)
      .withdrawLoot();
    const receipt = await cashoutTx.wait();
    const gasUsed = receipt.gasUsed * receipt.gasPrice;

    const operatorBalanceAfter = await ethers.provider.getBalance(attackerOperator.address);

    expect(await vulnerableVault.vaultBalance()).to.be.lt(ethers.parseEther("43"));
    expect(await vulnerableVault.vaultBalance()).to.be.gt(ethers.parseEther("41"));
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.equal(0n);
    expect(operatorBalanceAfter).to.be.gt(
      operatorBalanceBefore + ethers.parseEther("27") - gasUsed
    );
    expect(operatorBalanceAfter).to.be.lt(
      operatorBalanceBefore + ethers.parseEther("29") - gasUsed
    );
  });
});
