// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title NativeTransfer
/// @author SCSL
/// @notice Utility library for explicit native ETH transfers with custom errors.
library NativeTransfer {
    error NativeTransferInvalidRecipient(address recipient);
    error NativeTransferInvalidAmount();
    error NativeTransferFailed(address recipient, uint256 amount);

    function sendValue(address payable recipient, uint256 amount) internal {
        if (recipient == address(0)) {
            revert NativeTransferInvalidRecipient(address(0));
        }
        if (amount == 0) {
            revert NativeTransferInvalidAmount();
        }

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert NativeTransferFailed(recipient, amount);
        }
    }
}
