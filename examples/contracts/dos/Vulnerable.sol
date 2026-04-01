// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title PushRefundAuction
/// @author Solidity Security Lab
/// @notice Educational auction contract vulnerable to denial of service through refund reverts.
/// @dev This contract is intentionally vulnerable for training purposes.
contract PushRefundAuction {
    /// @notice Seller that receives the winning bid when the auction is settled.
    address public immutable seller;

    /// @notice Timestamp after which bidding is closed.
    uint256 public immutable auctionEndTime;

    /// @notice Current highest bidder.
    address public highestBidder;

    /// @notice Current highest bid.
    uint256 public highestBid;

    /// @notice Tracks whether the auction has already been settled.
    bool public settled;

    /// @notice Emitted when a new highest bid is accepted.
    event HighestBidIncreased(address indexed bidder, uint256 amount);

    /// @notice Emitted when the auction is settled.
    event AuctionSettled(address indexed winner, uint256 winningBid);

    constructor(uint256 biddingDurationSeconds) {
        require(biddingDurationSeconds > 0, "Duration must be greater than zero");
        seller = msg.sender;
        auctionEndTime = block.timestamp + biddingDurationSeconds;
    }

    modifier onlyBeforeEnd() {
        require(block.timestamp < auctionEndTime, "Auction already ended");
        _;
    }

    modifier onlyAfterEnd() {
        require(block.timestamp >= auctionEndTime, "Auction not ended");
        _;
    }

    /// @notice Places a new bid and refunds the previous leader inline.
    /// @dev CRITICAL BUG: the refund is pushed immediately and must succeed.
    function bid() external payable onlyBeforeEnd {
        require(msg.value > highestBid, "Bid too low");

        // CRITICAL BUG:
        // the contract attempts to refund the previous highest bidder inline.
        // If that recipient reverts in receive()/fallback(), the entire new bid reverts
        // and the auction can become permanently stuck.
        if (highestBidder != address(0)) {
            (bool success, ) = payable(highestBidder).call{value: highestBid}("");
            require(success, "Refund transfer failed");
        }

        highestBidder = msg.sender;
        highestBid = msg.value;

        emit HighestBidIncreased(msg.sender, msg.value);
    }

    /// @notice Settles the auction and transfers the winning bid to the seller.
    function settleAuction() external onlyAfterEnd {
        require(!settled, "Auction already settled");
        settled = true;

        if (highestBid > 0) {
            (bool success, ) = payable(seller).call{value: highestBid}("");
            require(success, "Payout transfer failed");
        }

        emit AuctionSettled(highestBidder, highestBid);
    }
}
