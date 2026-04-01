// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import {NoncedAuthorizations} from "../../../../library/auth/NoncedAuthorizations.sol";

contract NoncedAuthorizationsHarness is NoncedAuthorizations {
    function consumeNonce(address account) external returns (uint256) {
        return _useAuthorizationNonce(account);
    }

    function requireDeadline(uint256 deadline) external view {
        _requireActiveAuthorization(deadline);
    }
}
