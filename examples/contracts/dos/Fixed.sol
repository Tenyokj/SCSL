// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title PullRefundAuction
/// @author Solidity Security Lab
/// @notice Secure auction that stores refunds for later withdrawal instead of pushing them inline.
contract PullRefundAuction {
    /// @notice Seller that receives the winning bid when the auction is settled.
    address public immutable seller;

    /// @notice Timestamp after which bidding is closed.
    uint256 public immutable auctionEndTime;

    /// @notice Current highest bidder.
    address public highestBidder;

    /// @notice Current highest bid.
    uint256 public highestBid;

    /// @notice Refunds owed to outbid bidders.
    mapping(address bidder => uint256 amount) public pendingReturns;

    /// @notice Tracks whether the auction has already been settled.
    bool public settled;

    /// @notice Emitted when a new highest bid is accepted.
    event HighestBidIncreased(address indexed bidder, uint256 amount);

    /// @notice Emitted when a refund is queued.
    event RefundQueued(address indexed bidder, uint256 amount);

    /// @notice Emitted when a refund is withdrawn.
    event RefundWithdrawn(address indexed bidder, uint256 amount);

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

    /// @notice Places a new bid without forcing an inline refund to the previous leader.
    function bid() external payable onlyBeforeEnd {
        require(msg.value > highestBid, "Bid too low");

        // Safe pattern:
        // queue the refund instead of pushing it immediately.
        if (highestBidder != address(0)) {
            pendingReturns[highestBidder] += highestBid;
            emit RefundQueued(highestBidder, highestBid);
        }

        highestBidder = msg.sender;
        highestBid = msg.value;

        emit HighestBidIncreased(msg.sender, msg.value);
    }

    /// @notice Lets an outbid bidder withdraw their queued refund.
    function withdrawRefund() external {
        uint256 refundAmount = pendingReturns[msg.sender];
        require(refundAmount > 0, "No refund available");

        // Checks-Effects-Interactions:
        // zero the refund before the external transfer.
        pendingReturns[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
        require(success, "Refund withdrawal failed");

        emit RefundWithdrawn(msg.sender, refundAmount);
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
