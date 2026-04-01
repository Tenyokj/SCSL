// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

import {EIP1967SlotAccess} from "../../../../library/storage/EIP1967SlotAccess.sol";

contract EIP1967SlotAccessHarness {
    function admin() external view returns (address) {
        return EIP1967SlotAccess.getAdmin();
    }

    function implementation() external view returns (address) {
        return EIP1967SlotAccess.getImplementation();
    }

    function setAdmin(address newAdmin) external {
        EIP1967SlotAccess.setAdmin(newAdmin);
    }

    function setImplementation(address newImplementation) external {
        EIP1967SlotAccess.setImplementation(newImplementation);
    }
}
