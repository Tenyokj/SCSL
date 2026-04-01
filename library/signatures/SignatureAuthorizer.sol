// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title SignatureAuthorizer
/// @author SCSL
/// @notice Utility library for recovering and validating standard Ethereum signed messages.
library SignatureAuthorizer {
    error SignatureInvalidLength(uint256 length);
    error SignatureInvalidV(uint8 v);

    /// @notice Converts a 32-byte digest into an Ethereum Signed Message digest.
    function toEthSignedMessageHash(bytes32 messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
    }

    /// @notice Recovers the signer of an Ethereum signed message digest.
    function recoverSigner(bytes32 digest, bytes memory signature) internal pure returns (address) {
        if (signature.length != 65) {
            revert SignatureInvalidLength(signature.length);
        }

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        if (v != 27 && v != 28) {
            revert SignatureInvalidV(v);
        }

        return ecrecover(digest, v, r, s);
    }

    /// @notice Checks whether a signature was produced by an expected signer.
    function isAuthorizedSigner(
        bytes32 digest,
        bytes memory signature,
        address expectedSigner
    ) internal pure returns (bool) {
        return recoverSigner(digest, signature) == expectedSigner;
    }
}
