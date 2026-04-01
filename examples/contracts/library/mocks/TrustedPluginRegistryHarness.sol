// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import {TrustedPluginRegistry} from "../../../../library/proxy/TrustedPluginRegistry.sol";

contract TrustedPluginRegistryHarness is TrustedPluginRegistry {
    uint256 public storedValue;

    constructor(address initialOwner) TrustedPluginRegistry(initialOwner) {}

    function executeTrustedPlugin(address plugin, bytes calldata callData) external onlyOwner returns (bytes memory) {
        return _delegateToTrustedPlugin(plugin, callData);
    }
}

contract TrustedValuePlugin {
    function setStoredValue(uint256 newValue) external {
        assembly {
            sstore(3, newValue)
        }
    }
}

contract RevertingTrustedPlugin {
    function doRevert() external pure {
        revert("Plugin reverted");
    }
}
