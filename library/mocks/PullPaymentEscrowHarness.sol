// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import {PullPaymentEscrow} from "../payments/PullPaymentEscrow.sol";

contract PullPaymentEscrowHarness is PullPaymentEscrow {
    function queuePayment(address recipient) external payable {
        require(msg.value > 0, "No Ether supplied");
        _queuePayment(recipient, msg.value);
    }

    function withdrawMyPayment() external {
        _withdrawPayment(payable(msg.sender));
    }
}
