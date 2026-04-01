// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import {NativeTransfer} from "../../../../library/payments/NativeTransfer.sol";

contract NativeTransferHarness {
    function forward(address payable recipient) external payable {
        NativeTransfer.sendValue(recipient, msg.value);
    }
}
