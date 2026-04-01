// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title NoncedAuthorizations
/// @author SCSL
/// @notice Internal nonce and deadline helper for one-time authorizations.
/// @dev Useful for signed claims, permit-like flows, and replay-resistant off-chain approvals.
abstract contract NoncedAuthorizations {
    mapping(address account => uint256 nonce) private authorizationNonces;

    error AuthorizationExpired(uint256 deadline, uint256 currentTimestamp);

    /// @notice Returns the current nonce for an account.
    function authorizationNonce(address account) public view returns (uint256) {
        return authorizationNonces[account];
    }

    /// @notice Consumes and returns the current nonce for an account.
    function _useAuthorizationNonce(address account) internal returns (uint256 currentNonce) {
        currentNonce = authorizationNonces[account];
        authorizationNonces[account] = currentNonce + 1;
    }

    /// @notice Checks whether a deadline is still valid.
    function _requireActiveAuthorization(uint256 deadline) internal view {
        if (block.timestamp > deadline) {
            revert AuthorizationExpired(deadline, block.timestamp);
        }
    }
}
