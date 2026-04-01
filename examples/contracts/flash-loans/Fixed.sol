// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import "./Vulnerable.sol";

/// @title TrustedPriceOracle
/// @author Solidity Security Lab
/// @notice Simple trusted oracle used to decouple collateral valuation from manipulable AMM spot price.
contract TrustedPriceOracle {
    /// @notice ETH value of one collateral token, scaled by 1e18.
    uint256 public immutable priceEthPerToken;

    constructor(uint256 initialPriceEthPerToken) {
        require(initialPriceEthPerToken > 0, "Price must be greater than zero");
        priceEthPerToken = initialPriceEthPerToken;
    }

    function getPriceEthPerToken() external view returns (uint256) {
        return priceEthPerToken;
    }
}

/// @title SafeOracleLendingVault
/// @author Solidity Security Lab
/// @notice Safer lending vault that uses a trusted oracle instead of AMM spot price.
contract SafeOracleLendingVault {
    uint256 public constant LTV_BPS = 7500;

    FlashLoanLabToken public immutable collateralToken;
    TrustedPriceOracle public immutable trustedOracle;

    mapping(address borrower => uint256 amount) public collateralBalance;
    mapping(address borrower => uint256 amount) public debtBalance;

    event LiquiditySupplied(address indexed supplier, uint256 amount);
    event CollateralDeposited(address indexed borrower, uint256 amount);
    event Borrowed(address indexed borrower, uint256 amount);

    constructor(address tokenAddress, address oracleAddress) {
        require(tokenAddress != address(0), "Token cannot be zero");
        require(oracleAddress != address(0), "Oracle cannot be zero");

        collateralToken = FlashLoanLabToken(tokenAddress);
        trustedOracle = TrustedPriceOracle(oracleAddress);
    }

    /// @notice Supplies ETH liquidity that borrowers can later take out.
    function supplyLiquidity() external payable {
        require(msg.value > 0, "Liquidity amount zero");
        emit LiquiditySupplied(msg.sender, msg.value);
    }

    /// @notice Deposits collateral tokens into the lending vault.
    function depositCollateral(uint256 amount) external {
        require(amount > 0, "Collateral amount zero");

        require(
            collateralToken.transferFrom(msg.sender, address(this), amount),
            "Collateral transfer failed"
        );
        collateralBalance[msg.sender] += amount;

        emit CollateralDeposited(msg.sender, amount);
    }

    /// @notice Returns the ETH value of a borrower's collateral using a trusted price source.
    function collateralValueInEth(address borrower) public view returns (uint256) {
        uint256 priceEthPerToken = trustedOracle.getPriceEthPerToken();
        return (collateralBalance[borrower] * priceEthPerToken) / 1e18;
    }

    /// @notice Returns the maximum additional ETH a borrower may withdraw.
    function maximumBorrow(address borrower) public view returns (uint256) {
        uint256 maxDebtAllowed = (collateralValueInEth(borrower) * LTV_BPS) / 10_000;
        if (maxDebtAllowed <= debtBalance[borrower]) {
            return 0;
        }

        return maxDebtAllowed - debtBalance[borrower];
    }

    /// @notice Borrows ETH against token collateral.
    function borrow(uint256 amount) external {
        require(amount > 0, "Borrow amount zero");
        require(amount <= maximumBorrow(msg.sender), "Borrow amount too high");
        require(address(this).balance >= amount, "Vault lacks Ether");

        debtBalance[msg.sender] += amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Ether transfer failed");

        emit Borrowed(msg.sender, amount);
    }

    function vaultBalance() external view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable {
        emit LiquiditySupplied(msg.sender, msg.value);
    }
}
