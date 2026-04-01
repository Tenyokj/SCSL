// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import {TwoStepOwnable} from "../access/TwoStepOwnable.sol";

/// @title TrustedPluginRegistry
/// @author SCSL
/// @notice Base contract for systems that allow delegatecall only into explicitly trusted plugins.
/// @dev This is a defensive primitive for modular architectures that need controlled plugin execution.
abstract contract TrustedPluginRegistry is TwoStepOwnable {
    mapping(address plugin => bool trusted) private trustedPlugins;

    error TrustedPluginRegistryInvalidPlugin(address plugin);
    error TrustedPluginRegistryUntrustedPlugin(address plugin);
    error TrustedPluginRegistryDelegatecallFailed(address plugin);

    event TrustedPluginUpdated(address indexed plugin, bool trusted);

    constructor(address initialOwner) TwoStepOwnable(initialOwner) {}

    function isTrustedPlugin(address plugin) public view returns (bool) {
        return trustedPlugins[plugin];
    }

    function setTrustedPlugin(address plugin, bool trusted) external onlyOwner {
        if (plugin == address(0)) {
            revert TrustedPluginRegistryInvalidPlugin(address(0));
        }

        trustedPlugins[plugin] = trusted;
        emit TrustedPluginUpdated(plugin, trusted);
    }

    function _delegateToTrustedPlugin(
        address plugin,
        bytes memory callData
    ) internal returns (bytes memory result) {
        if (!trustedPlugins[plugin]) {
            revert TrustedPluginRegistryUntrustedPlugin(plugin);
        }

        (bool success, bytes memory returnData) = plugin.delegatecall(callData);
        if (!success) {
            revert TrustedPluginRegistryDelegatecallFailed(plugin);
        }

        return returnData;
    }
}
