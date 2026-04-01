// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import {SignatureAuthorizer} from "../../../../library/signatures/SignatureAuthorizer.sol";

contract SignatureAuthorizerHarness {
    function toEthSignedMessageHash(bytes32 messageHash) external pure returns (bytes32) {
        return SignatureAuthorizer.toEthSignedMessageHash(messageHash);
    }

    function recoverSigner(bytes32 digest, bytes calldata signature) external pure returns (address) {
        return SignatureAuthorizer.recoverSigner(digest, signature);
    }

    function isAuthorizedSigner(
        bytes32 digest,
        bytes calldata signature,
        address expectedSigner
    ) external pure returns (bool) {
        return SignatureAuthorizer.isAuthorizedSigner(digest, signature, expectedSigner);
    }
}
