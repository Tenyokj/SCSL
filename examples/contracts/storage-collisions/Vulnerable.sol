// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title CollidingVaultLogic
/// @author Solidity Security Lab
/// @notice Logic contract designed for a proxy-based vault, but using ordinary low slots for state.
/// @dev When used behind a naive proxy, these slots collide with proxy admin/implementation storage.
contract CollidingVaultLogic {
    /// @notice Intended owner of the vault logic.
    /// @dev Slot 0 in logic storage.
    address public owner;

    /// @notice Initialization version flag.
    /// @dev Slot 1 in logic storage.
    uint256 public initializedVersion;

    /// @notice User deposit balances.
    /// @dev Mapping seed lives at slot 2.
    mapping(address account => uint256 amount) public balances;

    event Initialized(address indexed owner);
    event OwnerConfigured(address indexed owner);
    event Deposited(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);

    /// @notice Initializes the logic contract state.
    /// @dev Perfectly normal for a standalone implementation, but dangerous behind a naive proxy.
    function initialize(address initialOwner) external {
        require(initialOwner != address(0), "Owner cannot be zero");
        require(initializedVersion == 0, "Already initialized");

        owner = initialOwner;
        initializedVersion = 1;

        emit Initialized(initialOwner);
    }

    /// @notice Reconfigures the logical owner.
    /// @dev Intentionally left without access control to simulate a real configuration bug.
    function configureOwner(address newOwner) external {
        require(newOwner != address(0), "Owner cannot be zero");

        owner = newOwner;

        emit OwnerConfigured(newOwner);
    }

    /// @notice Allows users to deposit Ether into the proxied vault.
    function deposit() external payable {
        require(msg.value > 0, "Deposit must be greater than zero");
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Allows users to withdraw their own balance from the proxied vault.
    function withdraw(uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");
        require(balances[msg.sender] >= amount, "Insufficient balance");

        balances[msg.sender] -= amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Ether transfer failed");

        emit Withdrawn(msg.sender, amount);
    }
}

/// @title CollidingProxyVault
/// @author Solidity Security Lab
/// @notice Naive proxy that stores admin and implementation in ordinary slots 0 and 1.
/// @dev This contract is intentionally vulnerable for training purposes.
contract CollidingProxyVault {
    /// @notice Proxy admin.
    /// @dev Stored in slot 0.
    address public admin;

    /// @notice Current implementation address.
    /// @dev Stored in slot 1.
    address public implementation;

    event EmergencyWithdraw(address indexed recipient, uint256 amount);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    constructor(address initialImplementation, address initialAdmin) {
        require(initialImplementation != address(0), "Implementation cannot be zero");
        require(initialAdmin != address(0), "Admin cannot be zero");

        implementation = initialImplementation;
        admin = initialAdmin;
    }

    /// @notice Admin-only emergency sweep.
    function emergencyWithdraw(address recipient) external onlyAdmin {
        require(recipient != address(0), "Recipient cannot be zero");

        uint256 amount = address(this).balance;
        require(amount > 0, "Vault is empty");

        (bool success, ) = payable(recipient).call{value: amount}("");
        require(success, "Ether transfer failed");

        emit EmergencyWithdraw(recipient, amount);
    }

    /// @notice Fallback delegatecall into the current implementation.
    fallback() external payable {
        _delegate(implementation);
    }

    receive() external payable {
        _delegate(implementation);
    }

    function _delegate(address target) internal {
        require(target != address(0), "Implementation not set");

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())

            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
