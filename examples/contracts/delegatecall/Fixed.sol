// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title TrustedPluginVault
/// @author Solidity Security Lab
/// @notice Secure vault that restricts delegatecall to owner-approved trusted plugins.
contract TrustedPluginVault {
    /// @notice Owner allowed to manage plugins and sweep funds.
    address public owner;

    /// @notice Example state updated by trusted plugins.
    uint256 public pluginExecutionCount;

    /// @notice Whitelist of plugins approved for delegatecall execution.
    mapping(address plugin => bool isTrusted) public trustedPlugins;

    /// @notice Emitted when Ether is deposited into the vault.
    event Deposited(address indexed sender, uint256 amount);

    /// @notice Emitted when trust status changes for a plugin.
    event PluginTrustUpdated(address indexed plugin, bool isTrusted);

    /// @notice Emitted after a trusted plugin executes.
    event PluginExecuted(address indexed plugin, bytes data);

    /// @notice Emitted when funds are swept from the vault.
    event FundsSwept(address indexed recipient, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor(address initialOwner) {
        require(initialOwner != address(0), "Owner cannot be zero");
        owner = initialOwner;
    }

    /// @notice Accepts Ether deposits from users.
    function deposit() external payable {
        require(msg.value > 0, "Deposit must be greater than zero");
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Updates the trust status of a plugin.
    function setTrustedPlugin(address plugin, bool isTrusted) external onlyOwner {
        require(plugin != address(0), "Plugin cannot be zero");
        trustedPlugins[plugin] = isTrusted;
        emit PluginTrustUpdated(plugin, isTrusted);
    }

    /// @notice Executes a plugin only if it is explicitly trusted and only if called by the owner.
    function runPlugin(address plugin, bytes calldata data) external onlyOwner {
        require(plugin != address(0), "Plugin cannot be zero");
        require(trustedPlugins[plugin], "Plugin not trusted");

        (bool success, ) = plugin.delegatecall(data);
        require(success, "Delegatecall failed");

        emit PluginExecuted(plugin, data);
    }

    /// @notice Sweeps the full vault balance to a recipient.
    function sweepFunds(address recipient) external onlyOwner {
        require(recipient != address(0), "Recipient cannot be zero");

        uint256 amount = address(this).balance;
        require(amount > 0, "Vault is empty");

        (bool success, ) = payable(recipient).call{value: amount}("");
        require(success, "Ether transfer failed");

        emit FundsSwept(recipient, amount);
    }

    /// @notice Returns the current Ether balance of the vault.
    function vaultBalance() external view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }
}

/// @title SafeCounterPlugin
/// @author Solidity Security Lab
/// @notice Benign plugin that updates slot 1 in the caller's storage layout.
/// @dev Slot 1 in TrustedPluginVault stores pluginExecutionCount.
contract SafeCounterPlugin {
    /// @notice Increments pluginExecutionCount in the caller when executed via delegatecall.
    function incrementExecutionCount() external {
        assembly {
            let currentValue := sload(1)
            sstore(1, add(currentValue, 1))
        }
    }
}
