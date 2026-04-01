// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title VulnerableVault
/// @author Solidity Security Lab
/// @notice Educational contract that simulates a realistic Ether vault with a critical
///         reentrancy vulnerability in the withdrawal flow.
/// @dev This contract is intentionally vulnerable for training purposes.
contract VulnerableVault {
    /// @notice Stores the internal balance of each user.
    mapping(address account => uint256 amount) public balances;

    /// @notice Emitted when a user deposits Ether.
    event Deposited(address indexed account, uint256 amount);

    /// @notice Emitted when a user withdraws Ether.
    event Withdrawn(address indexed account, uint256 amount);

    /// @notice Allows a user to deposit Ether into their internal balance.
    function deposit() external payable {
        // Reject empty deposits to keep the example closer to a realistic product.
        require(msg.value > 0, "Deposit must be greater than zero");

        // Increase the sender's internal accounting balance.
        balances[msg.sender] += msg.value;

        // Emit an event for observability and post-incident analysis.
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Withdraws a requested amount of Ether to the caller.
    /// @dev Vulnerability: the external call happens before the state update.
    function withdraw(uint256 amount) external {
        // Validate that the caller requests a non-zero withdrawal.
        require(amount > 0, "Amount must be greater than zero");

        // Cache the balance in memory before the external call.
        // This is a common mistake: the developer thinks they are working
        // with a trusted snapshot, but the external call can make it stale.
        uint256 currentBalance = balances[msg.sender];

        // Check that the internal accounting allows this withdrawal.
        require(currentBalance >= amount, "Insufficient balance");

        // CRITICAL BUG:
        // Ether is sent via low-level call before the internal balance is updated.
        // If the recipient is a contract, it can reenter withdraw() from receive()/fallback()
        // and keep withdrawing while this frame still sees the old state.
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Ether transfer failed");

        // State is updated too late and, even worse, from a stale memory snapshot.
        // Every nested call can see currentBalance == 1 ether and then write
        // balances[msg.sender] = 0 on unwind, ignoring how much Ether was already drained.
        balances[msg.sender] = currentBalance - amount;

        // The event looks normal even though the vault may already be drained.
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Returns the actual Ether balance held by the vault.
    function vaultBalance() external view returns (uint256) {
        // address(this).balance reflects real Ether held by the contract,
        // not only its internal accounting records.
        return address(this).balance;
    }
}
