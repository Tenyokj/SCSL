// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title FixedVault
/// @author Solidity Security Lab
/// @notice Fixed vault implementation protected against reentrancy.
/// @dev Demonstrates both the CEI pattern and a custom nonReentrant guard.
contract FixedVault {
    /// @notice Internal accounting of user deposits.
    mapping(address account => uint256 amount) public balances;

    /// @dev Minimal custom reentrancy lock without relying on an external library.
    bool private locked;

    /// @notice Emitted when a user deposits Ether.
    event Deposited(address indexed account, uint256 amount);

    /// @notice Emitted when a user withdraws Ether.
    event Withdrawn(address indexed account, uint256 amount);

    /// @dev Blocks reentry into protected functions during the same call chain.
    modifier nonReentrant() {
        // If the lock is already active, a callback is trying to reenter.
        require(!locked, "ReentrancyGuard: reentrant call");

        // Activate the lock before the function body executes.
        locked = true;

        _;

        // Release the lock after execution completes.
        locked = false;
    }

    /// @notice Allows a user to deposit Ether into the vault.
    function deposit() external payable {
        // Validate the deposit amount.
        require(msg.value > 0, "Deposit must be greater than zero");

        // Update internal accounting.
        balances[msg.sender] += msg.value;

        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Safely withdraws Ether to the caller.
    /// @dev Follows Checks-Effects-Interactions.
    function withdraw(uint256 amount) external nonReentrant {
        // Checks: validate inputs and available balance.
        require(amount > 0, "Amount must be greater than zero");
        require(balances[msg.sender] >= amount, "Insufficient balance");

        // Effects: update storage before any external interaction,
        // so a reentrant call sees the reduced balance.
        balances[msg.sender] -= amount;

        // Interactions: external call comes last.
        (bool success, ) = payable(msg.sender).call{value: amount}("");

        // If the transfer fails, revert the entire transaction including the state update.
        require(success, "Ether transfer failed");

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Returns the actual Ether balance held by the vault.
    function vaultBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
