// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title BlockCooldown
/// @author SCSL
/// @notice Helper for block-number-based cooldowns that avoid timestamp manipulation risk.
abstract contract BlockCooldown {
    error BlockCooldownNotReady(uint256 currentBlock, uint256 requiredBlock);
    error BlockCooldownInvalidLength();

    function _requireElapsedBlocks(uint256 unlockBlock) internal view {
        if (block.number < unlockBlock) {
            revert BlockCooldownNotReady(block.number, unlockBlock);
        }
    }

    function _nextUnlockBlock(uint256 cooldownBlocks) internal view returns (uint256) {
        if (cooldownBlocks == 0) {
            revert BlockCooldownInvalidLength();
        }

        return block.number + cooldownBlocks;
    }
}
