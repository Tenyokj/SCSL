// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title ExecutionConstraints
/// @author SCSL
/// @notice Utility library for deadline and slippage boundary checks.
library ExecutionConstraints {
    error ExecutionDeadlineExpired(uint256 deadline, uint256 currentTimestamp);
    error ExecutionInsufficientOutput(uint256 actualAmountOut, uint256 minimumAmountOut);

    /// @notice Reverts if the current block timestamp is already past the declared deadline.
    function enforceDeadline(uint256 deadline) internal view {
        if (block.timestamp > deadline) {
            revert ExecutionDeadlineExpired(deadline, block.timestamp);
        }
    }

    /// @notice Reverts if actual output is worse than the user-declared minimum.
    function enforceMinimumOutput(uint256 actualAmountOut, uint256 minimumAmountOut) internal pure {
        if (actualAmountOut < minimumAmountOut) {
            revert ExecutionInsufficientOutput(actualAmountOut, minimumAmountOut);
        }
    }
}
