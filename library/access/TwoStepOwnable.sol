// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title TwoStepOwnable
/// @author SCSL
/// @notice Ownership helper that requires the next owner to explicitly accept control.
/// @dev This pattern reduces the risk of permanently assigning ownership to the wrong address.
abstract contract TwoStepOwnable {
    address private currentOwner;
    address private pendingOwner;

    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    error OwnableNoPendingTransfer(address account);

    event OwnershipTransferStarted(address indexed previousOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }

        currentOwner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view returns (address) {
        return currentOwner;
    }

    function pendingOwnership() public view returns (address) {
        return pendingOwner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }

        pendingOwner = newOwner;
        emit OwnershipTransferStarted(currentOwner, newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) {
            revert OwnableNoPendingTransfer(msg.sender);
        }

        address previousOwner = currentOwner;
        currentOwner = msg.sender;
        pendingOwner = address(0);

        emit OwnershipTransferred(previousOwner, currentOwner);
    }

    function renounceOwnership() external onlyOwner {
        address previousOwner = currentOwner;
        currentOwner = address(0);
        pendingOwner = address(0);

        emit OwnershipTransferred(previousOwner, address(0));
    }

    function _checkOwner() internal view {
        if (msg.sender != currentOwner) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
    }
}
