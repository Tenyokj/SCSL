// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import {ExecutionConstraints} from "../../../../library/trading/ExecutionConstraints.sol";

contract ExecutionConstraintsHarness {
    function enforceDeadline(uint256 deadline) external view {
        ExecutionConstraints.enforceDeadline(deadline);
    }

    function enforceMinimumOutput(uint256 actualAmountOut, uint256 minimumAmountOut) external pure {
        ExecutionConstraints.enforceMinimumOutput(actualAmountOut, minimumAmountOut);
    }
}
