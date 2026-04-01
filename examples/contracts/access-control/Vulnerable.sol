// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title OriginBasedTreasury
/// @author Solidity Security Lab
/// @notice Educational treasury contract with a critical access-control flaw based on tx.origin.
/// @dev This contract is intentionally vulnerable for training purposes.
contract OriginBasedTreasury {
    /// @notice Current treasury owner.
    address public owner;

    /// @notice Emitted when Ether is deposited into the treasury.
    event Deposited(address indexed sender, uint256 amount);

    /// @notice Emitted when the treasury is drained by the owner workflow.
    event Swept(address indexed recipient, uint256 amount);

    constructor(address initialOwner) {
        require(initialOwner != address(0), "Owner cannot be zero");
        owner = initialOwner;
    }

    /// @notice Allows any user to deposit Ether into the treasury.
    function deposit() external payable {
        require(msg.value > 0, "Deposit must be greater than zero");
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Returns the current Ether balance of the treasury.
    function treasuryBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Sweeps the full treasury balance to a recipient.
    /// @dev CRITICAL BUG: authorization is based on tx.origin instead of msg.sender.
    function sweepTo(address recipient) external {
        require(recipient != address(0), "Recipient cannot be zero");

        // CRITICAL BUG:
        // tx.origin tracks the original EOA that started the transaction.
        // If the owner is tricked into calling a malicious intermediary contract,
        // tx.origin will still equal owner even though msg.sender is untrusted.
        require(tx.origin == owner, "Unauthorized origin");

        uint256 amount = address(this).balance;
        require(amount > 0, "Treasury is empty");

        (bool success, ) = payable(recipient).call{value: amount}("");
        require(success, "Ether transfer failed");

        emit Swept(recipient, amount);
    }

    /// @notice Accepts direct Ether transfers.
    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }
}
