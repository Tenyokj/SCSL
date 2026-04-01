<p align="center">
  <img src="../../../public/SCSL_banner.png" alt="SCSL banner" width="100%" style="max-height: 220px; object-fit: cover; object-position: center;" />
</p>

# STORAGE COLLISIONS: Full Educational Module on Proxy Storage Layout Collisions in Solidity

## Introduction

Storage collisions are one of the most important and subtle security topics in Solidity, especially in upgradeable and proxy-based architectures. Many developers eventually learn that a proxy uses `delegatecall` and that implementation contracts must preserve storage layout. But learning the slogan is not enough. To build secure systems, you need to understand why collisions happen, what exactly collides, and how that collision can turn into privilege escalation or full fund loss.

This module demonstrates a classic and extremely educational case:

- a proxy stores its own metadata, such as `admin` and `implementation`, in ordinary low storage slots;
- a logic contract also stores ordinary state variables in those same slots;
- the proxy forwards calls to the logic contract using `delegatecall`;
- the logic writes what it thinks are normal values like `owner` and `initialized`;
- in reality, those writes overwrite the proxy’s `admin` and `implementation`.

The consequence is severe. An attacker calls an unsafe owner-configuration function through the proxy, becomes proxy admin due to slot collision, and then drains all ETH using an admin-only emergency function.

This is not a toy issue. Storage collisions are central to proxy security, upgrade safety, and modular smart-contract architecture. They are one of the clearest examples of why understanding delegatecall at a storage level matters.

This module includes:

- a vulnerable proxy with colliding storage layout;
- a logic contract that looks ordinary in isolation;
- an attacker contract that weaponizes the collision;
- a safe proxy using isolated unstructured storage slots;
- tests proving the exploit and the mitigation;
- a detailed explanation of the underlying mechanics.

The key lesson is simple: **delegatecall does not only execute foreign code in your context. It also makes storage layout a security boundary.**

## What a Storage Collision Is

A storage collision happens when two contracts assume different meanings for the same storage slot, but one of them executes in the other’s storage context.

This is especially dangerous with proxies.

Suppose the proxy stores:

- slot `0` -> `admin`
- slot `1` -> `implementation`

And the logic contract stores:

- slot `0` -> `owner`
- slot `1` -> `initializedVersion`

If the proxy delegatecalls into the logic contract, then any write the logic contract makes to:

- slot `0`
- slot `1`

will actually change:

- the proxy’s `admin`
- the proxy’s `implementation`

That is a storage collision.

The logic contract thinks it is setting its own state. In reality, it is mutating core proxy metadata.

## Why Proxies Make This Dangerous

Delegatecall changes the normal relationship between code and storage:

- code comes from the implementation contract;
- storage belongs to the proxy.

That means the implementation’s declared layout must be compatible with the proxy’s actual storage layout.

If the proxy uses normal slots like `0`, `1`, `2` for its own metadata, and the logic contract also uses `0`, `1`, `2` for application state, those meanings overlap. The system becomes unsafe by design.

This is why modern upgradeable patterns use:

- EIP-1967 slots;
- carefully preserved layout ordering;
- storage gaps;
- unstructured storage patterns.

Without those disciplines, delegatecall-based architectures are extremely brittle.

## The Vulnerable Architecture in This Module

This module uses:

1. `CollidingProxyVault`
2. `CollidingVaultLogic`
3. `StorageCollisionAttacker`

### The proxy

The vulnerable proxy stores:

```solidity
address public admin;          // slot 0
address public implementation; // slot 1
```

It also exposes:

- an admin-only `emergencyWithdraw()`
- a fallback that delegatecalls to `implementation`

### The logic

The logic stores:

```solidity
address public owner;           // slot 0
uint256 public initializedVersion; // slot 1
mapping(address => uint256) public balances; // slot 2 seed
```

In a standalone contract, this would be fine.

Behind the vulnerable proxy, it is dangerous.

### The attacker

The attacker:

1. calls `configureOwner(address(this))` through the proxy;
2. causes the logic to write:
   - `owner = address(this)` -> overwrites proxy `admin`
3. then calls the proxy’s admin-only emergency withdrawal and drains all funds.

## Step-by-Step Attack Walkthrough

The tests model a realistic scenario:

- the proxy admin deploys a vault proxy;
- users begin depositing ETH through the proxied logic;
- the system is left uninitialized or incorrectly exposed;
- the attacker deploys an exploit contract.

Now the exploit happens:

1. The attacker calls `attack(proxyAddress)`.
2. The exploit contract sends:

```solidity
configureOwner(address(this))
```

to the proxy.

3. The proxy fallback delegatecalls into `CollidingVaultLogic.configureOwner()`.
4. Inside that logic:
   - `owner = address(this)` writes to slot `0`
5. Because this is delegatecall, slot `0` belongs to the proxy, not the logic contract.
6. The proxy’s `admin` is now the attacker contract.
7. The attacker contract calls the proxy’s direct admin-only `emergencyWithdraw()`.
8. The admin check passes.
9. The proxy sends all ETH to the attacker contract.
10. The attacker operator withdraws the stolen funds.

This is a complete privilege escalation caused purely by storage layout mismatch.

## Why a Single Slot Collision Is Enough

A subtle but important detail in this exploit is that the attacker does not need to corrupt every proxy field. Overwriting just one privileged slot is enough:

```solidity
owner = newOwner;              // slot 0
```

The attacker wants the admin overwrite. Once `admin` is controlled, the system’s trust boundary is already broken.

This is actually a useful lesson:

- storage collisions do not require a complicated write path;
- corrupting one privileged slot can already be catastrophic.

## EVM-Level Explanation

The key is delegatecall.

When the proxy executes:

```solidity
delegatecall(gas(), implementation, ...)
```

the implementation code runs as if:

- `address(this)` is the proxy;
- storage is the proxy’s storage;
- all `sload` and `sstore` operations read and write proxy slots.

So when the logic executes:

```solidity
owner = initialOwner;
```

that does not write to “logic owner.” It writes to whatever lives in slot `0` of the proxy.

That is the core mental model every auditor and upgradeable-contract engineer must have.

## Line-by-Line Analysis of `Vulnerable.sol`

### `CollidingProxyVault`

#### `address public admin;`

Stored in slot `0`. This is already risky. Proxy metadata in ordinary low slots is a red flag.

#### `address public implementation;`

Stored in slot `1`. Same problem.

#### `fallback()` and `receive()`

Both paths delegatecall into `implementation`. That means any function defined in the logic contract can execute against the proxy’s storage.

#### `emergencyWithdraw(address recipient)`

This function is reasonable in isolation. Proxies or vaults often need admin-only rescue capabilities. The problem is that the admin variable is no longer trustworthy once storage collision exists.

### `CollidingVaultLogic`

#### `address public owner;`

This looks harmless. But because it lives in slot `0`, it collides directly with proxy `admin`.

#### `uint256 public initializedVersion;`

This lives in slot `1`, colliding with proxy `implementation`.

#### `initialize(address initialOwner)`

This is the fatal function. It writes to slots `0` and `1`, assuming they belong to logic state. They do not.

The function itself is normal for upgradeable systems. The problem is not that initialization exists. The problem is that the proxy did not isolate its own metadata.

## Line-by-Line Analysis of `Attack.sol`

### `proxyAddress.call(abi.encodeWithSignature("initialize(address)", address(this)))`

This triggers the collision via fallback. The attacker does not need direct access to implementation internals. They only need the proxy to forward the call.

### `emergencyWithdraw(address(this))`

After the collision, the attacker contract is the proxy admin. It immediately uses that privilege to drain the vault.

### `withdrawLoot()`

After the drain, the stolen ETH sits inside the attacker contract and is forwarded to the operator.

## The Fixed Architecture: Unstructured Proxy Storage

The safe proxy in this module uses dedicated high-value slots for proxy metadata:

- `ADMIN_SLOT`
- `IMPLEMENTATION_SLOT`

These are EIP-1967-style unstructured storage slots, far away from the ordinary sequential layout used by the logic contract.

This means:

- logic `owner` in slot `0` no longer touches proxy `admin`;
- logic `initialized` in slot `1` no longer touches proxy `implementation`.

The logic can safely use normal layout for application state, while the proxy keeps its own metadata in isolated slots.

This is one of the most important design improvements in modern upgradeable systems.

## Why the Fixed Version Stops the Attack

In the fixed test, the attacker repeats the same attempt:

1. call `initialize(address(this))` through the proxy;
2. try to gain admin control;
3. try to drain funds.

But this time:

- `initialize()` writes only to the proxy’s ordinary slots `0` and `1`;
- proxy `admin()` is not stored there;
- proxy `implementation()` is not stored there.

So the collision no longer affects proxy metadata.

As a result:

- the attacker does not become admin;
- `emergencyWithdraw()` still rejects the attacker;
- the exploit reverts.

That is the correct outcome.

## Legitimate Functionality Still Works

The fixed module does not just “block the exploit.” It still supports the intended product behavior:

- owner initialization through the proxy;
- user deposits through delegated logic;
- user withdrawals through delegated logic.

This is an important engineering point. A good proxy-security fix should preserve:

- upgradeability assumptions;
- initialization workflow;
- user-facing logic behavior.

The fix should remove collision risk, not remove all usability.

## Real-World Context: Why Storage Collisions Matter

Storage collisions are central to proxy and upgradeability security. They have shaped how the ecosystem thinks about:

- proxy admin storage;
- implementation slots;
- initializer design;
- upgrade-safe storage gaps;
- inheritance ordering;
- append-only layout rules.

Many critical upgradeability failures ultimately reduce to one of these questions:

- what slot does this variable really occupy?
- who else assumes a meaning for that same slot?
- what happens if delegatecall writes there?

This is why serious audits always include explicit storage-layout review when proxies are involved.

## Remediation Strategies

### Use Unstructured Storage for Proxy Metadata

Do not store proxy-critical variables such as admin and implementation in ordinary low slots.

### Follow EIP-1967 or Equivalent Proven Slot Conventions

These conventions reduce collision risk and improve tooling compatibility.

### Preserve Logic Storage Layout Carefully Across Upgrades

Even if the proxy is safe, implementation upgrades can still introduce collisions if new variables are inserted incorrectly.

### Review Initializers as Security-Critical Entry Points

Initialization is often the first place where state gets written. If proxy metadata and logic metadata are not properly separated, initializer flows become dangerous immediately.

### Test Through the Proxy, Not Just the Logic Contract

Many storage issues only appear when code is executed through delegatecall.

## Best Practices

- Store proxy metadata in isolated slots.
- Use proven proxy patterns and standards.
- Treat storage layout as part of the security model.
- Review slot ordering on every upgrade.
- Keep initializer logic tightly controlled.
- Test delegatecall behavior against actual proxy storage.
- Audit admin, implementation, and ownership slots as high-priority assets.
- Never assume a logic contract is safe in isolation if it will run behind a proxy.

## Common Developer Mistakes

### Mistake 1: “The logic contract looks fine on its own”

Logic contracts are not executed on their own in proxy systems. Their safety depends on proxy storage context.

### Mistake 2: “If the variable names are different, they will not collide”

Storage does not care about variable names. It cares about slot positions.

### Mistake 3: “Initialization is harmless setup”

Initialization is one of the most dangerous moments in an upgradeable system because it often writes privileged state for the first time.

### Mistake 4: “Only upgrades can cause storage issues”

No. Even the very first deployment can be broken if proxy metadata and logic metadata overlap.

### Mistake 5: “Delegatecall problems are only about malicious logic”

Not always. Even honest logic can be dangerous if it is executed against an incompatible storage layout.

## How to Read the Tests in This Module

The vulnerable tests show:

- users depositing ETH through a naive proxy;
- the attacker calling `initialize()` through fallback;
- proxy `admin` being overwritten;
- proxy `implementation` being corrupted;
- the attacker draining the full balance through an admin-only rescue function.

The fixed tests show:

- the same attack attempt now fails;
- proxy metadata remains intact;
- legitimate initialization, deposit, and withdrawal through the proxy still work.

This is exactly what a good mitigation should achieve: keep the architecture functional while removing the collision surface.

## Why This Module Feels Like a Real Audit Case

Many proxy tutorials say “be careful with storage layout” but do not make the risk concrete. Real audits do not stop there. Auditors ask:

- what is stored in slot `0` of the proxy?
- what does the implementation think slot `0` means?
- can initialization overwrite proxy metadata?
- can a collision lead directly to privilege escalation or fund loss?

This module is built around those practical questions. It shows not only that a collision exists, but exactly how it turns into admin takeover and theft.

## Conclusion

Storage collisions are one of the clearest examples of why proxy security requires low-level understanding. A proxy and an implementation do not merely need compatible function selectors. They need compatible storage assumptions.

The key lessons from this module are:

- delegatecall makes storage layout a security boundary;
- ordinary low slots are unsafe for proxy metadata;
- initialization and admin paths become dangerous immediately when slots collide.

If you build the habit of asking, “What lives in this slot in the proxy, and what does the implementation think lives there?”, you are thinking like a smart-contract security engineer. That is exactly the mindset this lab is designed to build.
