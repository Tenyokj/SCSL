<p align="center">
  <img src="../../../public/SCSL_banner.png" alt="SCSL banner" width="100%" style="max-height: 220px; object-fit: cover; object-position: center;" />
</p>

# DELEGATECALL: Full Educational Module on Delegatecall Abuse in Solidity

## Introduction

`delegatecall` is one of the most powerful and dangerous features in the EVM. It allows one contract to execute code that lives at another address, but to do so in the storage context of the calling contract. That single sentence is the key to understanding both modern proxy patterns and some of the worst smart-contract vulnerabilities ever discovered.

At a high level, `delegatecall` is useful because it enables:

- upgradeable proxies;
- modular plugin systems;
- shared library logic;
- strategy architectures;
- composable execution flows.

But it is also dangerous because when you `delegatecall` into external code, that code can read and write **your** storage, not its own. If the callee is malicious, poorly validated, or layout-incompatible, it can overwrite your owner, corrupt your balances, disable your guards, or destroy invariants you thought were safe.

This module demonstrates a realistic version of the problem: a vault that tries to support modular plugins, but exposes a public `delegatecall` path to arbitrary plugin addresses. An attacker supplies a malicious plugin, overwrites the vault owner in storage slot `0`, and immediately drains the vault.

This module includes:

- a vulnerable plugin-based vault;
- an attacker contract that hijacks ownership through delegatecall;
- a fixed vault that restricts delegatecall to trusted, owner-approved plugins;
- tests showing both the exploit and the mitigation;
- a detailed explanation of why delegatecall abuse is so dangerous.

The core lesson is simple: **delegatecall is not “calling another contract.” It is lending another contract your own storage and execution authority.**

## What `delegatecall` Actually Does

When contract A uses `delegatecall` to contract B:

- code is taken from contract B;
- storage is read and written in contract A;
- `msg.sender` remains the original caller of contract A;
- `address(this)` remains contract A.

This is very different from a normal `call`.

With a normal `call`:

- code runs in the callee;
- storage belongs to the callee;
- value and state changes happen in the callee’s context.

With `delegatecall`:

- code comes from the callee;
- state belongs to the caller.

That means the callee’s code can do things like:

- write to slot `0`;
- overwrite the owner;
- clear a pause flag;
- change an implementation address;
- manipulate balances or approvals;
- brick the contract entirely.

This power is why `delegatecall` must be treated as a critical trust boundary, not as a casual extension mechanism.

## Why Delegatecall Vulnerabilities Are So Severe

Most Solidity vulnerabilities let an attacker influence a function or a state transition. Delegatecall abuse can let an attacker define the state transition itself.

If the target contract allows arbitrary or weakly validated delegatecall, the attacker may gain:

- ownership takeover;
- full balance access;
- upgrade control;
- arbitrary storage corruption;
- system-wide privilege escalation.

In other words, delegatecall bugs often collapse the contract’s entire security model, not just one isolated function.

## The Vulnerable Contract: `PluginVault`

The vulnerable contract in this module is a vault with a plugin execution system. The idea is plausible: a team wants off-chain automation, modular features, or strategy logic that can be executed against the vault’s state. So they add:

```solidity
function runPlugin(address plugin, bytes calldata data) external {
    (bool success, ) = plugin.delegatecall(data);
    require(success, "Delegatecall failed");
}
```

That is the core bug.

The contract has:

- an `owner` in storage slot `0`;
- a `pluginExecutionCount` in storage slot `1`;
- Ether deposits from users;
- an owner-only `sweepFunds()` function.

Because `runPlugin()` is public and does not validate plugin trust, anyone can supply malicious code and run it directly against the vault’s storage.

## Step-by-Step Attack Walkthrough

The test scenario is realistic:

- the vault has a real owner;
- honest users deposit 9 ETH into the vault;
- the attacker deploys a malicious helper contract.

Now the exploit begins:

1. The attacker calls `attack(vaultAddress)` on the malicious contract.
2. The malicious contract prepares payload data for `overwriteOwner(address(this))`.
3. It calls `vault.runPlugin(address(this), payload)`.
4. The vault performs `delegatecall` into the attacker contract.
5. The attacker contract’s `overwriteOwner()` function executes in the vault’s storage context.
6. `sstore(0, address(this))` writes the attacker contract address into storage slot `0`.
7. The vault now believes the attacker contract is its owner.
8. The attacker contract immediately calls `vault.sweepFunds(address(this))`.
9. The owner-only check passes because `msg.sender` is now the attacker contract, which the vault believes is the owner.
10. The vault transfers all Ether to the attacker contract.
11. The attacker operator later withdraws the stolen Ether.

This is not just a bug in one function. It is total state compromise through execution-context abuse.

## How the Storage Hijack Works

The critical detail is storage layout.

In `PluginVault`, slot `0` stores:

```solidity
address public owner;
```

The attacker contract contains:

```solidity
function overwriteOwner(address newOwner) external {
    assembly {
        sstore(0, newOwner)
    }
}
```

When this function runs normally inside the attacker contract, it writes to slot `0` of the attacker contract.

When it runs through `delegatecall` from the vault, it writes to slot `0` of the vault.

That is the essence of delegatecall abuse: code location and storage location are decoupled.

## EVM-Level Execution Flow

The sequence is worth understanding carefully.

### Before `delegatecall`

- `PluginVault.owner = realOwner`
- `PluginVault.balance = 9 ETH`
- `DelegatecallHijacker.operator = attackerEOA`

### During `runPlugin(address(this), payload)`

The vault executes:

```solidity
plugin.delegatecall(data)
```

Inside the delegated code:

- `address(this)` is still the vault;
- storage writes hit the vault;
- `msg.sender` is still the original external caller of `runPlugin()`, which in this case is the attacker contract.

When `overwriteOwner()` does:

```solidity
sstore(0, newOwner)
```

it overwrites the vault’s owner slot.

### After `delegatecall`

- `PluginVault.owner = attackerContract`
- the attacker contract can now pass `onlyOwner` checks
- the vault is fully compromised

## Line-by-Line Analysis of `Vulnerable.sol`

### `address public owner;`

This is the most critical storage slot in the contract. In many real contracts, slot `0` or other low slots store the most sensitive data: owner, implementation, admin, guardian, or core accounting variables.

### `function runPlugin(address plugin, bytes calldata data) external`

This is the vulnerable entry point. There are two failures here:

1. anyone can call it;
2. anyone can choose the plugin address.

That means delegatecall trust is fully attacker-controlled.

### `plugin.delegatecall(data)`

This is where the contract gives away its storage context. The problem is not that delegatecall exists. The problem is that it is exposed without:

- ownership restriction;
- whitelist validation;
- storage-layout guarantees;
- trusted-code assumptions.

### `sweepFunds(address recipient)`

On its own, this function is reasonable. Owner-only fund sweeping is a common treasury feature. But once the attacker overwrites `owner`, the protection becomes meaningless.

## Line-by-Line Analysis of `Attack.sol`

### `attack(address targetAddress)`

This function chains the exploit end to end:

1. determine the target’s balance;
2. trigger malicious delegatecall;
3. call the now-authorized owner-only sweep;
4. emit an event confirming the drain.

This is a realistic exploit flow. Attackers often combine state takeover and value extraction in one transaction.

### `overwriteOwner(address newOwner)`

This is the core payload. It is intentionally tiny because malicious delegatecall payloads often are. A small storage write can be enough to collapse the security boundary of an entire contract.

### `withdrawLoot()`

After the state takeover and fund sweep, the stolen Ether sits inside the attacker contract. This function forwards it to the attacker operator.

## The Fixed Contract: `TrustedPluginVault`

The secure version keeps the plugin concept but restores trust boundaries.

It adds:

- `onlyOwner` on plugin execution;
- a whitelist of trusted plugin addresses;
- explicit plugin approval through `setTrustedPlugin()`.

The secure execution flow is:

```solidity
require(msg.sender == owner, "Only owner");
require(trustedPlugins[plugin], "Plugin not trusted");
(bool success, ) = plugin.delegatecall(data);
require(success, "Delegatecall failed");
```

This is still a powerful pattern, but now it is explicit. Delegatecall only happens when:

- the owner intentionally triggers it;
- the plugin has already been approved;
- the plugin is part of the trusted system boundary.

That does not eliminate all delegatecall risk, but it removes the arbitrary execution path that made the vulnerable vault trivial to exploit.

## Why the Fixed Version Stops the Attack

When the attacker tries the same exploit against `TrustedPluginVault`, the call sequence becomes:

1. attacker operator calls `DelegatecallHijacker.attack()`
2. `DelegatecallHijacker` calls `fixedVault.runPlugin(...)`
3. inside the vault, `msg.sender == attackerContract`
4. the vault checks:

```solidity
require(msg.sender == owner, "Only owner");
```

5. the call fails immediately

Even if the owner were the caller, the vault would still require:

```solidity
require(trustedPlugins[plugin], "Plugin not trusted");
```

So the attack fails on both authorization and trust validation.

## Legitimate Delegatecall Use Case in the Fixed Version

One reason delegatecall bugs keep appearing is that delegatecall itself is not always wrong. It is often used legitimately in:

- upgradeable proxies;
- modular account systems;
- internal library patterns;
- execution routers.

To show that secure delegatecall is still possible, the fixed module includes `SafeCounterPlugin`, a benign plugin that increments `pluginExecutionCount` in slot `1`. The owner explicitly approves this plugin and then executes:

```solidity
incrementExecutionCount()
```

through `runPlugin()`.

This demonstrates the important nuance:

- delegatecall is not automatically insecure;
- arbitrary delegatecall is insecure;
- delegatecall must be constrained by ownership, trust, and storage-awareness.

## Real-World Context: Why Delegatecall Bugs Matter Historically

Delegatecall-related failures have been central to some of the most important Solidity security incidents and design lessons. One of the most famous examples is the Parity multisig library pattern, where shared logic and privileged initialization behavior created catastrophic outcomes. Even when the exact root cause differs between incidents, the broader lesson is consistent:

- shared execution logic is powerful;
- privilege boundaries become subtle;
- storage context must be treated with extreme care.

Delegatecall is often involved in the most severe classes of bugs because it is tightly connected to upgradeability and ownership. If those go wrong, the attacker often gains near-total control.

## Remediation Strategies

### Restrict Delegatecall to Trusted Code

Never allow arbitrary users to supply arbitrary delegatecall targets.

### Use Ownership or Role Checks

Delegatecall execution should usually be protected by:

- `onlyOwner`
- `onlyRole`
- dedicated module-manager permissions

### Maintain Strict Storage-Layout Discipline

If a plugin or implementation expects certain storage slots, the calling contract must guarantee that layout deliberately. Accidental layout mismatch can be just as dangerous as malicious intent.

### Prefer Normal `call` When You Do Not Need Shared Storage

If you only need to invoke another contract’s logic and do not need that logic to mutate your own storage, use `call`, not `delegatecall`.

### Audit Every Delegatecall Surface Explicitly

Whenever you see delegatecall in an audit, ask:

- who chooses the target?
- who chooses the calldata?
- what storage slots can the callee touch?
- what privileges exist in those slots?
- can the delegatecalled code reach privileged flows afterward?

## Best Practices

- Treat delegatecall as a critical trust boundary.
- Never expose arbitrary delegatecall to untrusted callers.
- Whitelist trusted implementations or plugins.
- Gate delegatecall execution behind strong access control.
- Keep storage layouts intentionally designed and documented.
- Use normal external calls when shared storage is unnecessary.
- Add adversarial tests with malicious delegatecall targets.
- Review owner, admin, implementation, and balance slots as top-priority assets.

## Common Developer Mistakes

### Mistake 1: “It is just a plugin system”

A plugin system based on delegatecall is not “just” an extension mechanism. It is privileged code execution inside your contract.

### Mistake 2: “The plugin has no Ether, so it cannot hurt the vault”

Delegatecalled code does not need its own Ether. It runs against the vault’s state and can unlock the vault’s own privileges.

### Mistake 3: “We will trust callers not to abuse the plugin API”

Public execution surfaces must be secure even when used maliciously. Trusting caller intent is not security.

### Mistake 4: “If the callee contract looks simple, delegatecall is probably safe”

Even tiny payloads can be devastating. A single `sstore(0, ...)` can be enough to seize ownership.

### Mistake 5: “Only proxies need delegatecall review”

No. Any library pattern, module system, plugin executor, automation hook, or strategy router that uses delegatecall must be reviewed with the same seriousness.

## How to Read the Tests in This Module

The vulnerable tests demonstrate:

- honest users funding a vault;
- an attacker using a malicious delegatecall payload;
- ownership being overwritten;
- the vault being drained;
- the attacker operator cashing out afterward.

The fixed tests demonstrate:

- arbitrary delegatecall takeover attempts now fail;
- the owner remains unchanged;
- the vault balance remains safe;
- a trusted plugin can still be executed intentionally by the owner.

That combination is important. A good fix should not merely “turn everything off.” It should preserve legitimate modular behavior while removing arbitrary execution.

## Why This Module Feels Like a Real Audit Case

Many delegatecall tutorials stop at explaining that “delegatecall uses caller storage.” That is necessary, but not enough. In real audits, the questions are sharper:

- can the caller choose the target?
- can the caller choose the calldata?
- can the callee overwrite ownership or implementation slots?
- what happens after ownership is hijacked?
- is there any trusted use case that still needs to work?

This module is built around those practical questions. It models a plausible plugin system, a concrete ownership-takeover exploit, and a fix that still allows safe owner-approved plugin execution.

## Conclusion

Delegatecall is one of the highest-risk features in Solidity because it allows external code to execute with your contract’s storage and authority. Used carefully, it can power advanced architectures. Used carelessly, it can destroy your entire trust model.

The key lessons from this module are:

- delegatecall executes foreign code against local storage;
- arbitrary delegatecall is equivalent to arbitrary state mutation;
- ownership and plugin trust must be enforced before delegatecall happens.

If you build the habit of asking, “Whose code is this, whose storage will it touch, and who chose that code path?”, you are thinking like a smart-contract security engineer. That is exactly the mindset this lab is designed to build.
