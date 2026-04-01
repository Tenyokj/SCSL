// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title ReplayableSignatureVault
/// @author Solidity Security Lab
/// @notice Educational vault vulnerable to signature replay because claims do not use nonces or one-time tracking.
/// @dev This contract is intentionally vulnerable for training purposes.
contract ReplayableSignatureVault {
    /// @notice Trusted signer that authorizes withdrawals off-chain.
    address public immutable authorizedSigner;

    /// @notice Emitted when Ether is deposited into the vault.
    event Deposited(address indexed sender, uint256 amount);

    /// @notice Emitted when a signed claim is executed.
    event Claimed(address indexed beneficiary, uint256 amount);

    constructor(address signer) {
        require(signer != address(0), "Signer cannot be zero");
        authorizedSigner = signer;
    }

    /// @notice Allows users to fund the vault.
    function deposit() external payable {
        require(msg.value > 0, "Deposit must be greater than zero");
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Returns the current Ether balance of the vault.
    function vaultBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Claims Ether using an off-chain signature.
    /// @dev CRITICAL BUG: the signed message has no nonce, no expiry, and no replay protection.
    function claim(uint256 amount, bytes calldata signature) external {
        require(amount > 0, "Amount must be greater than zero");
        require(address(this).balance >= amount, "Vault lacks Ether");

        bytes32 digest = _toEthSignedMessageHash(
            keccak256(abi.encodePacked(msg.sender, amount, address(this)))
        );
        require(_recoverSigner(digest, signature) == authorizedSigner, "Invalid signature");

        // CRITICAL BUG:
        // the contract never records that this signed authorization was already used.
        // The same signature can be replayed over and over again by the same beneficiary.
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Ether transfer failed");

        emit Claimed(msg.sender, amount);
    }

    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    function _toEthSignedMessageHash(bytes32 messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
    }

    function _recoverSigner(bytes32 digest, bytes calldata signature) internal pure returns (address) {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        require(v == 27 || v == 28, "Invalid signature v");
        return ecrecover(digest, v, r, s);
    }
}
