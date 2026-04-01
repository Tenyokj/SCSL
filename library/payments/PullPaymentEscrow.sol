// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title PullPaymentEscrow
/// @author SCSL
/// @notice Internal pull-payment primitive that queues ETH for later withdrawal.
/// @dev Useful when liveness matters and direct push payments could be blocked by recipient behavior.
abstract contract PullPaymentEscrow {
    mapping(address account => uint256 amount) private credits;

    error PullPaymentInvalidRecipient(address recipient);
    error PullPaymentInvalidAmount();
    error PullPaymentNothingDue(address recipient);
    error PullPaymentTransferFailed(address recipient, uint256 amount);

    event PaymentQueued(address indexed recipient, uint256 amount);
    event PaymentWithdrawn(address indexed recipient, uint256 amount);

    function payments(address recipient) public view returns (uint256) {
        return credits[recipient];
    }

    function _queuePayment(address recipient, uint256 amount) internal {
        if (recipient == address(0)) {
            revert PullPaymentInvalidRecipient(address(0));
        }
        if (amount == 0) {
            revert PullPaymentInvalidAmount();
        }

        credits[recipient] += amount;
        emit PaymentQueued(recipient, amount);
    }

    function _withdrawPayment(address payable recipient) internal returns (uint256 amount) {
        amount = credits[recipient];
        if (amount == 0) {
            revert PullPaymentNothingDue(recipient);
        }

        credits[recipient] = 0;

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            credits[recipient] = amount;
            revert PullPaymentTransferFailed(recipient, amount);
        }

        emit PaymentWithdrawn(recipient, amount);
    }
}
