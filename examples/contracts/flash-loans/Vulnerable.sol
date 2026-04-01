// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title FlashLoanLabToken
/// @author Solidity Security Lab
/// @notice Minimal ERC20-like token used in the flash-loan oracle manipulation module.
contract FlashLoanLabToken {
    string public constant name = "Flash Loan Lab Token";
    string public constant symbol = "FLLT";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;

    mapping(address account => uint256 amount) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        require(to != address(0), "Mint to zero");
        require(amount > 0, "Mint amount zero");

        totalSupply += amount;
        balanceOf[to] += amount;

        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowedAmount = allowance[from][msg.sender];
        require(allowedAmount >= amount, "Allowance exceeded");

        allowance[from][msg.sender] = allowedAmount - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "Transfer to zero");
        require(balanceOf[from] >= amount, "Insufficient balance");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        emit Transfer(from, to, amount);
    }
}

interface IFlashLoanEtherReceiver {
    function onFlashLoan(uint256 amount) external payable;
}

/// @title FlashLoanEtherLender
/// @author Solidity Security Lab
/// @notice Minimal ETH flash-loan pool used to demonstrate atomic price manipulation.
contract FlashLoanEtherLender {
    event FlashLoanExecuted(address indexed borrower, uint256 amount);

    constructor() payable {
        require(msg.value > 0, "Initial liquidity required");
    }

    /// @notice Lends ETH for the duration of a single transaction and expects full repayment.
    function flashLoan(uint256 amount) external {
        uint256 balanceBefore = address(this).balance;
        require(amount > 0, "Loan amount zero");
        require(balanceBefore >= amount, "Insufficient liquidity");

        IFlashLoanEtherReceiver(msg.sender).onFlashLoan{value: amount}(amount);

        require(address(this).balance >= balanceBefore, "Flash loan not repaid");
        emit FlashLoanExecuted(msg.sender, amount);
    }

    receive() external payable {}
}

/// @title FlashLoanSpotAMM
/// @author Solidity Security Lab
/// @notice Minimal ETH/token AMM whose spot price is vulnerable to in-tx manipulation.
contract FlashLoanSpotAMM {
    FlashLoanLabToken public immutable token;

    event LiquidityAdded(address indexed provider, uint256 ethAmount, uint256 tokenAmount);
    event TokensPurchased(address indexed buyer, uint256 ethIn, uint256 tokensOut);

    constructor(address tokenAddress) {
        require(tokenAddress != address(0), "Token cannot be zero");
        token = FlashLoanLabToken(tokenAddress);
    }

    /// @notice Adds liquidity to the AMM.
    function addLiquidity(uint256 tokenAmount) external payable {
        require(msg.value > 0, "ETH amount zero");
        require(tokenAmount > 0, "Token amount zero");

        require(token.transferFrom(msg.sender, address(this), tokenAmount), "Token transfer failed");
        emit LiquidityAdded(msg.sender, msg.value, tokenAmount);
    }

    /// @notice Buys tokens with ETH using a simple constant-product style quote.
    function buyTokens() external payable returns (uint256 tokensOut) {
        require(msg.value > 0, "ETH amount zero");

        uint256 ethReserveBefore = address(this).balance - msg.value;
        uint256 tokenReserveBefore = token.balanceOf(address(this));
        require(ethReserveBefore > 0, "Insufficient ETH reserve");
        require(tokenReserveBefore > 0, "Insufficient token reserve");

        tokensOut = (msg.value * tokenReserveBefore) / (ethReserveBefore + msg.value);
        require(tokensOut > 0, "Token amount zero");
        require(token.transfer(msg.sender, tokensOut), "Token transfer failed");

        emit TokensPurchased(msg.sender, msg.value, tokensOut);
    }

    /// @notice Returns the current spot price of 1 token in ETH, scaled by 1e18.
    function spotPriceEthPerToken() external view returns (uint256) {
        uint256 tokenReserveBefore = token.balanceOf(address(this));
        require(tokenReserveBefore > 0, "Insufficient token reserve");

        return (address(this).balance * 1e18) / tokenReserveBefore;
    }
}

/// @title SpotOracleLendingVault
/// @author Solidity Security Lab
/// @notice Educational lending vault vulnerable because it trusts instantaneous AMM spot price as collateral oracle.
/// @dev This contract is intentionally vulnerable for training purposes.
contract SpotOracleLendingVault {
    uint256 public constant LTV_BPS = 7500;

    FlashLoanLabToken public immutable collateralToken;
    FlashLoanSpotAMM public immutable oracleAmm;

    mapping(address borrower => uint256 amount) public collateralBalance;
    mapping(address borrower => uint256 amount) public debtBalance;

    event LiquiditySupplied(address indexed supplier, uint256 amount);
    event CollateralDeposited(address indexed borrower, uint256 amount);
    event Borrowed(address indexed borrower, uint256 amount);

    constructor(address tokenAddress, address ammAddress) {
        require(tokenAddress != address(0), "Token cannot be zero");
        require(ammAddress != address(0), "AMM cannot be zero");

        collateralToken = FlashLoanLabToken(tokenAddress);
        oracleAmm = FlashLoanSpotAMM(ammAddress);
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

    /// @notice Returns the ETH value of a borrower's collateral using AMM spot price.
    function collateralValueInEth(address borrower) public view returns (uint256) {
        uint256 priceEthPerToken = oracleAmm.spotPriceEthPerToken();
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
    /// @dev CRITICAL BUG: collateral valuation depends on a spot price that can be manipulated within the same transaction.
    function borrow(uint256 amount) external {
        require(amount > 0, "Borrow amount zero");
        require(amount <= maximumBorrow(msg.sender), "Borrow amount too high");
        require(address(this).balance >= amount, "Vault lacks Ether");

        // CRITICAL BUG:
        // the vault trusts the AMM's instantaneous spot price, which can be moved
        // via a flash loan immediately before borrow() executes.
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
