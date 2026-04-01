// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title UncheckedRewardVault
/// @author Solidity Security Lab
/// @notice Educational Ether vault vulnerable to accounting underflow through incorrect unchecked arithmetic.
/// @dev This contract is intentionally vulnerable for training purposes.
contract UncheckedRewardVault {
    /// @notice Conversion rate between internal credits and redeemable wei.
    uint256 public constant CREDIT_PER_WEI = 1e18;

    /// @notice Internal redeemable credits assigned to each user.
    mapping(address account => uint256 amount) public rewardCredits;

    /// @notice Emitted when Ether is deposited and credits are minted.
    event Deposited(address indexed account, uint256 weiAmount, uint256 mintedCredits);

    /// @notice Emitted when credits are redeemed for Ether.
    event Redeemed(address indexed account, uint256 burnedCredits, uint256 weiAmount);

    /// @notice Allows a user to deposit Ether and receive redeemable credits.
    function deposit() external payable {
        require(msg.value > 0, "Deposit must be greater than zero");

        uint256 mintedCredits = msg.value * CREDIT_PER_WEI;

        // The deposit path itself is not the vulnerable part in this module.
        rewardCredits[msg.sender] += mintedCredits;

        emit Deposited(msg.sender, msg.value, mintedCredits);
    }

    /// @notice Redeems credits for Ether.
    /// @dev CRITICAL BUG: the function burns credits inside unchecked arithmetic without first
    ///      verifying that the caller actually has enough credits.
    function redeem(uint256 creditAmount) external {
        require(creditAmount > 0, "Credit amount must be greater than zero");

        uint256 weiAmount = creditAmount / CREDIT_PER_WEI;
        require(weiAmount > 0, "Credit amount too small");
        require(address(this).balance >= weiAmount, "Vault lacks Ether");

        // CRITICAL BUG:
        // the code assumes subtraction will be safe, but it never checks
        // rewardCredits[msg.sender] >= creditAmount before entering unchecked.
        // If the caller has zero credits, this underflows and wraps to a huge uint256,
        // while the Ether transfer below still succeeds.
        unchecked {
            rewardCredits[msg.sender] -= creditAmount;
        }

        (bool success, ) = payable(msg.sender).call{value: weiAmount}("");
        require(success, "Ether transfer failed");

        emit Redeemed(msg.sender, creditAmount, weiAmount);
    }

    /// @notice Returns the current Ether balance of the vault.
    function vaultBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
