// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title TimestampLastBuyerGame
/// @author Solidity Security Lab
/// @notice Educational jackpot game vulnerable to timestamp manipulation near the cooldown boundary.
/// @dev This contract is intentionally vulnerable for training purposes.
contract TimestampLastBuyerGame {
    /// @notice Minimum amount required to become the current leader.
    uint256 public constant MIN_BUY_IN = 1 ether;

    /// @notice Current leader allowed to claim the pot after cooldown.
    address public lastBuyer;

    /// @notice Timestamp of the latest qualifying buy.
    uint256 public lastBuyTimestamp;

    /// @notice Cooldown duration after which the leader can claim the pot.
    uint256 public immutable cooldownSeconds;

    /// @notice Emitted when a user becomes the latest buyer.
    event BuyIn(address indexed buyer, uint256 amount, uint256 timestamp);

    /// @notice Emitted when the pot is claimed.
    event PotClaimed(address indexed winner, uint256 amount);

    constructor(uint256 cooldownDurationSeconds) {
        require(cooldownDurationSeconds > 0, "Cooldown must be greater than zero");
        cooldownSeconds = cooldownDurationSeconds;
    }

    /// @notice Allows a user to become the current leader by adding Ether to the pot.
    function buyIn() external payable {
        require(msg.value >= MIN_BUY_IN, "Buy-in too small");

        lastBuyer = msg.sender;
        lastBuyTimestamp = block.timestamp;

        emit BuyIn(msg.sender, msg.value, block.timestamp);
    }

    /// @notice Lets the latest buyer claim the full pot after the cooldown.
    /// @dev CRITICAL BUG: the protocol fully trusts block.timestamp for a sharp economic boundary.
    function claimPot() external {
        require(msg.sender == lastBuyer, "Only last buyer");

        // CRITICAL BUG:
        // using block.timestamp as a strict economic gate assumes the timestamp
        // precisely represents real elapsed wall-clock time.
        // A validator can skew the block timestamp slightly near the boundary,
        // which can allow the leader to claim earlier than users expect.
        require(
            block.timestamp >= lastBuyTimestamp + cooldownSeconds,
            "Cooldown not finished"
        );

        uint256 amount = address(this).balance;
        require(amount > 0, "Pot is empty");

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Ether transfer failed");

        emit PotClaimed(msg.sender, amount);
    }

    /// @notice Returns the current Ether balance of the pot.
    function potBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
