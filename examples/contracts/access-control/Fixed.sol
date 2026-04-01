// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title RoleBasedTreasury
/// @author Solidity Security Lab
/// @notice Secure treasury that uses msg.sender-based authorization and two-step ownership transfer.
contract RoleBasedTreasury {
    /// @notice Current active owner.
    address public owner;

    /// @notice Candidate owner that must explicitly accept the role.
    address public pendingOwner;

    /// @notice Emitted when Ether is deposited.
    event Deposited(address indexed sender, uint256 amount);

    /// @notice Emitted when ownership transfer is initiated.
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when ownership transfer is completed.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when the treasury is swept.
    event Swept(address indexed recipient, uint256 amount);

    modifier onlyOwner() {
        // Authorization must be based on msg.sender, not tx.origin.
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor(address initialOwner) {
        require(initialOwner != address(0), "Owner cannot be zero");
        owner = initialOwner;
    }

    /// @notice Allows any user to deposit Ether into the treasury.
    function deposit() external payable {
        require(msg.value > 0, "Deposit must be greater than zero");
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Starts a two-step ownership transfer.
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Owner cannot be zero");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    /// @notice Accepts ownership after transferOwnership has been called.
    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "Only pending owner");

        address previousOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);

        emit OwnershipTransferred(previousOwner, owner);
    }

    /// @notice Sweeps the full treasury balance to a recipient.
    function sweepTo(address recipient) external onlyOwner {
        require(recipient != address(0), "Recipient cannot be zero");

        uint256 amount = address(this).balance;
        require(amount > 0, "Treasury is empty");

        (bool success, ) = payable(recipient).call{value: amount}("");
        require(success, "Ether transfer failed");

        emit Swept(recipient, amount);
    }

    /// @notice Returns the current Ether balance of the treasury.
    function treasuryBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Accepts direct Ether transfers.
    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }
}
