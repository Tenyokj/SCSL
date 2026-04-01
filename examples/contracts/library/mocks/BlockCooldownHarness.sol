// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import {BlockCooldown} from "../../../../library/time/BlockCooldown.sol";

contract BlockCooldownHarness is BlockCooldown {
    uint256 public unlockBlock;

    function arm(uint256 cooldownBlocks) external {
        unlockBlock = _nextUnlockBlock(cooldownBlocks);
    }

    function executeWhenReady() external view {
        _requireElapsedBlocks(unlockBlock);
    }
}
