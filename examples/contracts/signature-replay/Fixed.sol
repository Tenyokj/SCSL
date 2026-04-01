// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title NoncedSignatureVault
/// @author Solidity Security Lab
/// @notice Secure vault that uses nonce-based, expiring withdrawal signatures.
contract NoncedSignatureVault {
    /// @notice Trusted signer that authorizes withdrawals off-chain.
    address public immutable authorizedSigner;

    /// @notice Per-beneficiary nonce used to make each signature one-time only.
    mapping(address beneficiary => uint256 nonce) public nonces;

    /// @notice Emitted when Ether is deposited into the vault.
    event Deposited(address indexed sender, uint256 amount);

    /// @notice Emitted when a signed claim is executed.
    event Claimed(address indexed beneficiary, uint256 amount, uint256 nonce);

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

    /// @notice Claims Ether using a one-time signed authorization.
    function claim(uint256 amount, uint256 deadline, bytes calldata signature) external {
        require(amount > 0, "Amount must be greater than zero");
        require(block.timestamp <= deadline, "Signature expired");
        require(address(this).balance >= amount, "Vault lacks Ether");

        uint256 currentNonce = nonces[msg.sender];
        bytes32 digest = _toEthSignedMessageHash(
            keccak256(
                abi.encodePacked(
                    block.chainid,
                    address(this),
                    msg.sender,
                    amount,
                    currentNonce,
                    deadline
                )
            )
        );
        require(_recoverSigner(digest, signature) == authorizedSigner, "Invalid signature");

        // Mark the signature as consumed before transferring Ether.
        nonces[msg.sender] = currentNonce + 1;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Ether transfer failed");

        emit Claimed(msg.sender, amount, currentNonce);
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
