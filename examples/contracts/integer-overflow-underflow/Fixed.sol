// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title SafeRewardVault
/// @author Solidity Security Lab
/// @notice Secure Ether vault that uses checked accounting for internal credits.
contract SafeRewardVault {
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
        rewardCredits[msg.sender] += mintedCredits;

        emit Deposited(msg.sender, msg.value, mintedCredits);
    }

    /// @notice Redeems credits for Ether using explicit balance checks and safe arithmetic.
    function redeem(uint256 creditAmount) external {
        require(creditAmount > 0, "Credit amount must be greater than zero");

        uint256 weiAmount = creditAmount / CREDIT_PER_WEI;
        require(weiAmount > 0, "Credit amount too small");
        require(rewardCredits[msg.sender] >= creditAmount, "Insufficient credits");
        require(address(this).balance >= weiAmount, "Vault lacks Ether");

        // Effects happen before the external interaction.
        rewardCredits[msg.sender] -= creditAmount;

        (bool success, ) = payable(msg.sender).call{value: weiAmount}("");
        require(success, "Ether transfer failed");

        emit Redeemed(msg.sender, creditAmount, weiAmount);
    }

    /// @notice Returns the current Ether balance of the vault.
    function vaultBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
