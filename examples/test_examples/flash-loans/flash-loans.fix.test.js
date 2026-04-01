import { expect } from "chai";
import hre from "hardhat";

describe("Flash loan module: trusted-oracle lending vault", function () {
  let connection;

  before(async function () {
    // In Hardhat 3, network helpers are available through a network connection.
    connection = await hre.network.connect();
  });

  async function deployFlashLoanFixedFixture() {
    // Create a realistic actor set:
    // AMM liquidity provider, lending-liquidity provider, honest borrower, and attacker operator.
    const { ethers } = connection;
    const [ammLiquidityProvider, lendingLiquidityProvider, honestBorrower, attackerOperator] =
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

    const oracleFactory = await ethers.getContractFactory("TrustedPriceOracle");
    const oracle = await oracleFactory.deploy(ethers.parseEther("0.1"));
    await oracle.waitForDeployment();

    const fixedVaultFactory = await ethers.getContractFactory("SafeOracleLendingVault");
    const fixedVault = await fixedVaultFactory.deploy(
      await token.getAddress(),
      await oracle.getAddress()
    );
    await fixedVault.waitForDeployment();

    const attackerFactory = await ethers.getContractFactory("FlashLoanPriceManipulationAttacker");
    const attackerContract = await attackerFactory
      .connect(attackerOperator)
      .deploy(
        await lender.getAddress(),
        await amm.getAddress(),
        await token.getAddress(),
        await fixedVault.getAddress()
      );
    await attackerContract.waitForDeployment();

    await token.mint(ammLiquidityProvider.address, ethers.parseEther("1000"));
    await token
      .connect(ammLiquidityProvider)
      .approve(await amm.getAddress(), ethers.parseEther("1000"));
    await amm
      .connect(ammLiquidityProvider)
      .addLiquidity(ethers.parseEther("1000"), { value: ethers.parseEther("100") });

    await fixedVault
      .connect(lendingLiquidityProvider)
      .supplyLiquidity({ value: ethers.parseEther("150") });

    // Give an honest borrower real collateral for a normal borrow path.
    await token.mint(honestBorrower.address, ethers.parseEther("100"));
    await token
      .connect(honestBorrower)
      .approve(await fixedVault.getAddress(), ethers.parseEther("100"));

    return {
      ethers,
      ammLiquidityProvider,
      lendingLiquidityProvider,
      honestBorrower,
      attackerOperator,
      token,
      lender,
      amm,
      oracle,
      fixedVault,
      attackerContract,
    };
  }

  it("prevents the flash-loan oracle manipulation because borrowing uses a trusted price source", async function () {
    const { networkHelpers } = connection;
    const { ethers, lender, fixedVault, attackerOperator, attackerContract } =
      await networkHelpers.loadFixture(deployFlashLoanFixedFixture);

    expect(await fixedVault.vaultBalance()).to.equal(
      ethers.parseEther("150")
    );

    await expect(
      attackerContract.connect(attackerOperator).attack(ethers.parseEther("80"))
    ).to.be.revertedWith("Flash loan repayment failed");

    expect(await ethers.provider.getBalance(await lender.getAddress())).to.equal(
      ethers.parseEther("120")
    );
    expect(await fixedVault.vaultBalance()).to.equal(
      ethers.parseEther("150")
    );
    expect(
      await ethers.provider.getBalance(await attackerContract.getAddress())
    ).to.equal(0n);
  });

  it("still allows an honest borrower to use real collateral and borrow within the trusted oracle limit", async function () {
    const { networkHelpers } = connection;
    const { ethers, honestBorrower, fixedVault } =
      await networkHelpers.loadFixture(deployFlashLoanFixedFixture);

    await fixedVault.connect(honestBorrower).depositCollateral(ethers.parseEther("100"));

    expect(await fixedVault.collateralValueInEth(honestBorrower.address)).to.equal(
      ethers.parseEther("10")
    );
    expect(await fixedVault.maximumBorrow(honestBorrower.address)).to.equal(
      ethers.parseEther("7.5")
    );

    const borrowerBalanceBefore = await ethers.provider.getBalance(honestBorrower.address);

    const borrowTx = await fixedVault.connect(honestBorrower).borrow(ethers.parseEther("7"));
    const receipt = await borrowTx.wait();
    const gasUsed = receipt.gasUsed * receipt.gasPrice;

    const borrowerBalanceAfter = await ethers.provider.getBalance(honestBorrower.address);

    expect(await fixedVault.vaultBalance()).to.equal(
      ethers.parseEther("143")
    );
    expect(await fixedVault.debtBalance(honestBorrower.address)).to.equal(
      ethers.parseEther("7")
    );
    expect(borrowerBalanceAfter).to.equal(
      borrowerBalanceBefore + ethers.parseEther("7") - gasUsed
    );
  });
});
