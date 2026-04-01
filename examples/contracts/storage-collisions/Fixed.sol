// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title SafeVaultLogic
/// @author Solidity Security Lab
/// @notice Logic contract intended for use behind an unstructured-storage proxy.
contract SafeVaultLogic {
    /// @notice Intended owner of the vault logic.
    address public owner;

    /// @notice Initialization version flag.
    uint256 public initializedVersion;

    /// @notice User deposit balances.
    mapping(address account => uint256 amount) public balances;

    event Initialized(address indexed owner);
    event OwnerConfigured(address indexed owner);
    event Deposited(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);

    function initialize(address initialOwner) external {
        require(initialOwner != address(0), "Owner cannot be zero");
        require(initializedVersion == 0, "Already initialized");

        owner = initialOwner;
        initializedVersion = 1;

        emit Initialized(initialOwner);
    }

    /// @notice Reconfigures the logical owner without touching proxy metadata.
    function configureOwner(address newOwner) external {
        require(newOwner != address(0), "Owner cannot be zero");

        owner = newOwner;

        emit OwnerConfigured(newOwner);
    }

    function deposit() external payable {
        require(msg.value > 0, "Deposit must be greater than zero");
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");
        require(balances[msg.sender] >= amount, "Insufficient balance");

        balances[msg.sender] -= amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Ether transfer failed");

        emit Withdrawn(msg.sender, amount);
    }
}

/// @title SafeSlotProxyVault
/// @author Solidity Security Lab
/// @notice Proxy that stores core proxy metadata in dedicated unstructured storage slots.
contract SafeSlotProxyVault {
    // EIP-1967-style slots for proxy metadata.
    bytes32 private constant ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 private constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    event EmergencyWithdraw(address indexed recipient, uint256 amount);

    modifier onlyAdmin() {
        require(msg.sender == admin(), "Only admin");
        _;
    }

    constructor(address initialImplementation, address initialAdmin) {
        require(initialImplementation != address(0), "Implementation cannot be zero");
        require(initialAdmin != address(0), "Admin cannot be zero");

        _setImplementation(initialImplementation);
        _setAdmin(initialAdmin);
    }

    function admin() public view returns (address currentAdmin) {
        assembly {
            currentAdmin := sload(ADMIN_SLOT)
        }
    }

    function implementation() public view returns (address currentImplementation) {
        assembly {
            currentImplementation := sload(IMPLEMENTATION_SLOT)
        }
    }

    function emergencyWithdraw(address recipient) external onlyAdmin {
        require(recipient != address(0), "Recipient cannot be zero");

        uint256 amount = address(this).balance;
        require(amount > 0, "Vault is empty");

        (bool success, ) = payable(recipient).call{value: amount}("");
        require(success, "Ether transfer failed");

        emit EmergencyWithdraw(recipient, amount);
    }

    fallback() external payable {
        _delegate(implementation());
    }

    receive() external payable {
        _delegate(implementation());
    }

    function _setAdmin(address newAdmin) internal {
        assembly {
            sstore(ADMIN_SLOT, newAdmin)
        }
    }

    function _setImplementation(address newImplementation) internal {
        assembly {
            sstore(IMPLEMENTATION_SLOT, newImplementation)
        }
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
