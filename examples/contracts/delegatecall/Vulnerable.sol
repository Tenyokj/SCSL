// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.28;

/// @title PluginVault
/// @author Solidity Security Lab
/// @notice Educational vault vulnerable to arbitrary delegatecall into attacker-controlled code.
/// @dev This contract is intentionally vulnerable for training purposes.
contract PluginVault {
    /// @notice Owner allowed to sweep funds from the vault.
    address public owner;

    /// @notice Example state updated by trusted automation plugins.
    uint256 public pluginExecutionCount;

    /// @notice Emitted when Ether is deposited into the vault.
    event Deposited(address indexed sender, uint256 amount);

    /// @notice Emitted after a plugin executes through delegatecall.
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

    /// @notice Executes arbitrary plugin code in the vault's storage context.
    /// @dev CRITICAL BUG: anyone can choose any plugin address and execute it via delegatecall.
    function runPlugin(address plugin, bytes calldata data) external {
        require(plugin != address(0), "Plugin cannot be zero");

        // CRITICAL BUG:
        // delegatecall runs external code against this contract's storage layout.
        // Because there is no access control and no plugin whitelist,
        // an attacker can supply malicious bytecode that overwrites owner or other state.
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
