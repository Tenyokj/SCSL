// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import {ReentrancyGuard} from "../../../../library/guards/ReentrancyGuard.sol";

interface IReentrancyProbe {
    function reenter() external;
}

contract ReentrancyGuardHarness is ReentrancyGuard {
    uint256 public executionCount;

    event ProtectedCallExecuted(address indexed caller, uint256 executionCount);

    function protectedIncrement() external nonReentrant {
        executionCount += 1;
        emit ProtectedCallExecuted(msg.sender, executionCount);
    }

    function callProbe(address probe) external nonReentrant {
        executionCount += 1;
        IReentrancyProbe(probe).reenter();
        emit ProtectedCallExecuted(msg.sender, executionCount);
    }
}

contract ReentrancyProbe {
    ReentrancyGuardHarness public immutable target;

    constructor(address targetAddress) {
        target = ReentrancyGuardHarness(targetAddress);
    }

    function reenter() external {
        target.protectedIncrement();
    }
}
