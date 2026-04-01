// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import {BalanceAccounting} from "../../../../library/accounting/BalanceAccounting.sol";

contract BalanceAccountingHarness is BalanceAccounting {
    function credit(address account, uint256 amount) external returns (uint256) {
        return _creditBalance(account, amount);
    }

    function debit(address account, uint256 amount) external returns (uint256) {
        return _debitBalance(account, amount);
    }
}
