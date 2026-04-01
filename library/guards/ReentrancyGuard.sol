// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title ReentrancyGuard
/// @author SCSL
/// @notice Lightweight guard that blocks nested entry into protected functions.
/// @dev Intended for contracts that need a simple, production-friendly nonReentrant modifier.
abstract contract ReentrancyGuard {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private guardState = NOT_ENTERED;

    error ReentrancyGuardReentrantCall();

    modifier nonReentrant() {
        _enterReentrancyGuard();
        _;
        _exitReentrancyGuard();
    }

    /// @notice Returns whether the current execution context is already inside a guarded section.
    function reentrancyGuardEntered() public view returns (bool) {
        return guardState == ENTERED;
    }

    function _enterReentrancyGuard() internal {
        if (guardState == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        guardState = ENTERED;
    }

    function _exitReentrancyGuard() internal {
        guardState = NOT_ENTERED;
    }
}
