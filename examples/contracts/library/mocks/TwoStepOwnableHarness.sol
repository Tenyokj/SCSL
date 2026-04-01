// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import {TwoStepOwnable} from "../../../../library/access/TwoStepOwnable.sol";

contract TwoStepOwnableHarness is TwoStepOwnable {
    uint256 public protectedCounter;

    constructor(address initialOwner) TwoStepOwnable(initialOwner) {}

    function ownerIncrement() external onlyOwner {
        protectedCounter += 1;
    }
}
