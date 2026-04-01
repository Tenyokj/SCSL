// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title BlockBasedLastBuyerGame
/// @author Solidity Security Lab
/// @notice Safer jackpot game that gates claims by block count instead of timestamp boundaries.
contract BlockBasedLastBuyerGame {
    /// @notice Minimum amount required to become the current leader.
    uint256 public constant MIN_BUY_IN = 1 ether;

    /// @notice Current leader allowed to claim the pot after cooldown blocks.
    address public lastBuyer;

    /// @notice Block number of the latest qualifying buy.
    uint256 public lastBuyBlock;

    /// @notice Cooldown measured in blocks.
    uint256 public immutable cooldownBlocks;

    /// @notice Emitted when a user becomes the latest buyer.
    event BuyIn(address indexed buyer, uint256 amount, uint256 blockNumber);

    /// @notice Emitted when the pot is claimed.
    event PotClaimed(address indexed winner, uint256 amount);

    constructor(uint256 cooldownDurationBlocks) {
        require(cooldownDurationBlocks > 0, "Cooldown must be greater than zero");
        cooldownBlocks = cooldownDurationBlocks;
    }

    /// @notice Allows a user to become the current leader by adding Ether to the pot.
    function buyIn() external payable {
        require(msg.value >= MIN_BUY_IN, "Buy-in too small");

        lastBuyer = msg.sender;
        lastBuyBlock = block.number;

        emit BuyIn(msg.sender, msg.value, block.number);
    }

    /// @notice Lets the latest buyer claim the full pot after enough blocks have passed.
    function claimPot() external {
        require(msg.sender == lastBuyer, "Only last buyer");
        require(block.number >= lastBuyBlock + cooldownBlocks, "Cooldown not finished");

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
