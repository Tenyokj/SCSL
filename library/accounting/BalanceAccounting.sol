// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title BalanceAccounting
/// @author SCSL
/// @notice Internal helper for explicit credit and debit accounting.
/// @dev Useful for vaults, reward systems, and queued withdrawal flows.
abstract contract BalanceAccounting {
    mapping(address account => uint256 amount) private trackedBalances;

    error BalanceAccountingInvalidAccount(address account);
    error BalanceAccountingInvalidAmount();
    error BalanceAccountingInsufficientBalance(
        address account,
        uint256 availableBalance,
        uint256 requiredBalance
    );

    event BalanceCredited(address indexed account, uint256 amount, uint256 newBalance);
    event BalanceDebited(address indexed account, uint256 amount, uint256 newBalance);

    function balanceOf(address account) public view returns (uint256) {
        return trackedBalances[account];
    }

    function _creditBalance(address account, uint256 amount) internal returns (uint256 newBalance) {
        if (account == address(0)) {
            revert BalanceAccountingInvalidAccount(address(0));
        }
        if (amount == 0) {
            revert BalanceAccountingInvalidAmount();
        }

        newBalance = trackedBalances[account] + amount;
        trackedBalances[account] = newBalance;

        emit BalanceCredited(account, amount, newBalance);
    }

    function _debitBalance(address account, uint256 amount) internal returns (uint256 newBalance) {
        if (account == address(0)) {
            revert BalanceAccountingInvalidAccount(address(0));
        }
        if (amount == 0) {
            revert BalanceAccountingInvalidAmount();
        }

        uint256 availableBalance = trackedBalances[account];
        if (availableBalance < amount) {
            revert BalanceAccountingInsufficientBalance(account, availableBalance, amount);
        }

        newBalance = availableBalance - amount;
        trackedBalances[account] = newBalance;

        emit BalanceDebited(account, amount, newBalance);
    }
}
