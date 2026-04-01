// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title EIP1967SlotAccess
/// @author SCSL
/// @notice Helpers for reading and writing proxy metadata using EIP-1967 slots.
library EIP1967SlotAccess {
    bytes32 internal constant ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    error EIP1967InvalidAdmin(address admin);
    error EIP1967InvalidImplementation(address implementation);

    function getAdmin() internal view returns (address currentAdmin) {
        assembly {
            currentAdmin := sload(ADMIN_SLOT)
        }
    }

    function setAdmin(address newAdmin) internal {
        if (newAdmin == address(0)) {
            revert EIP1967InvalidAdmin(address(0));
        }

        assembly {
            sstore(ADMIN_SLOT, newAdmin)
        }
    }

    function getImplementation() internal view returns (address currentImplementation) {
        assembly {
            currentImplementation := sload(IMPLEMENTATION_SLOT)
        }
    }

    function setImplementation(address newImplementation) internal {
        if (newImplementation == address(0)) {
            revert EIP1967InvalidImplementation(address(0));
        }

        assembly {
            sstore(IMPLEMENTATION_SLOT, newImplementation)
        }
    }
}
