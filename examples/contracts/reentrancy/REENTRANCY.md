<p align="center">
  <img src="../../../public/SCSL_banner.png" alt="SCSL banner" width="100%" style="max-height: 220px; object-fit: cover; object-position: center;" />
</p>

# REENTRANCY: Full Educational Module on Reentrancy Vulnerabilities

## Introduction

Reentrancy is one of the most famous and, at the same time, one of the most misunderstood vulnerabilities in Solidity. At a surface level, the idea seems simple: a contract sends Ether to an external address, and that external address manages to call back into the vulnerable function before the original contract updates its internal state. In practice, however, reentrancy matters not because it is a “clever `receive()` trick,” but because it breaks a dangerous developer assumption: “inside a function, state changes happen linearly and predictably.” In the EVM, that assumption stops being safe the moment an external call is involved. Every external interaction transfers control. As soon as you use `call`, you must assume you have temporarily lost control over execution.

This module presents reentrancy not as a toy example, but as a full educational case study that feels closer to a real audit scenario. It includes:

- a vulnerable Ether vault;
- a real attacker contract;
- a secure fixed version;
- tests that demonstrate a successful drain and prove that the mitigation works;
- a detailed explanation of why the exploit works at the EVM level.

The goal is not just to show what breaks, but to build the right engineering instinct: every external call is a possible context switch, and every context switch is a potential attack surface.

## What Reentrancy Is

Reentrancy happens when a contract performs an external call before finishing a security-critical state update, and the called party gets a chance to enter the original contract again and repeat a sensitive operation while the old state is still visible.

The key idea is this: Solidity code looks sequential, but the EVM executes it through message calls. The moment a contract performs an external interaction, whether through `call`, `delegatecall`, an interface call to another contract, or an Ether transfer to a contract address, execution may move into untrusted code. That untrusted code can call back into your contract before your invariants are restored.

In practice, it often looks like this:

1. A user or contract calls `withdraw`.
2. The contract checks the caller’s balance.
3. The contract sends Ether using `call`.
4. The recipient’s `receive()` function calls `withdraw` again.
5. The original contract still has not reduced the balance.
6. The condition `balances[msg.sender] >= amount` is still true.
7. The process repeats until the pool is drained.

That is the classic reentrancy loop.

## How It Works Inside the EVM

To understand the vulnerability deeply, you need to understand message-call mechanics.

When `withdraw` is called, the EVM:

1. Creates a new execution context.
2. Loads state from storage, such as the caller’s balance.
3. Evaluates `require` checks.
4. Reaches an external call like `call{value: amount}("")`.
5. Transfers control, Ether, and the remaining gas to the recipient.

If the recipient is an EOA, no code executes and control usually returns immediately.

If the recipient is a contract, the EVM attempts to execute:

- `receive()`, when calldata is empty and the function exists;
- `fallback()`, if `receive()` is absent or calldata does not match a function selector.

This is the exact point where the attacker gets a reentry window.

It is important to understand that an external call does not “pause the function safely.” It genuinely hands control to another contract. While the original function is still incomplete, that other contract can create a fresh call back into the vulnerable contract. This produces nested execution:

- `Vault.withdraw()`
- `Attacker.receive()`
- `Vault.withdraw()`
- `Attacker.receive()`
- `Vault.withdraw()`

Each new frame sees the state as it exists at the moment of entry. If the critical storage update has not happened yet, the check may pass again.

Historically, some developers relied on `transfer` and `send` because they forwarded only 2300 gas. After gas-cost changes such as EIP-1884, that approach stopped being a reliable general-purpose defense. Modern best practice is not to treat gas stipends as a security boundary. The correct defense is sound state-transition logic: Checks-Effects-Interactions and/or a reentrancy guard.

## Why `VulnerableVault` Is Vulnerable

The vulnerable contract in this module stores user balances in a `mapping`. A user deposits Ether using `deposit()` and can later call `withdraw(amount)`.

The dangerous logic looks like this:

```solidity
uint256 currentBalance = balances[msg.sender];
require(currentBalance >= amount, "Insufficient balance");
(bool success, ) = payable(msg.sender).call{value: amount}("");
balances[msg.sender] = currentBalance - amount;
```

The bug is in the order of operations:

- the external call happens first;
- storage is updated only afterward.

That means `balances[msg.sender]` still reflects the old value while the external call is in progress. If `msg.sender` is a malicious contract, it can exploit the window between the `call` and the final balance write.

## Step-by-Step Attack Walkthrough

Consider the scenario used in the test suite:

- Alice deposits 5 ETH.
- Bob deposits 5 ETH.
- The vault now contains 10 ETH belonging to honest users.
- The attacker deposits 1 ETH to obtain an internal balance entry.

Now the exploit begins:

1. The attacker calls `attack()` and sends 1 ETH.
2. `ReentrancyAttacker` forwards that Ether into `target.deposit{value: 1 ether}()`.
3. The attacker now has `balances[attacker] == 1 ether`.
4. The attacker calls `target.withdraw(1 ether)`.
5. `VulnerableVault` verifies that the balance is sufficient.
6. `VulnerableVault` sends 1 ETH back to the attacker using `call`.
7. Because the recipient is a contract, the EVM executes `receive()`.
8. Inside `receive()`, the attacker sees that the vault still has Ether and calls `withdraw(1 ether)` again.
9. The second iteration passes because the original call has not yet finalized the state update.
10. The loop repeats until the vault’s Ether is exhausted.
11. Only after the recursive chain returns does each stack frame continue toward its late state write.

This vulnerable vault contains an additional realistic mistake: it caches `currentBalance` in memory before the external call, and after the call returns it writes the stale value `currentBalance - amount` back into storage. Every nested reentrant invocation sees the same snapshot and eventually writes `0`, regardless of how many times Ether was already sent out. That is why the attack succeeds cleanly in Solidity 0.8 without running into arithmetic underflow.

## Line-by-Line Analysis of `Vulnerable.sol`

### `mapping(address account => uint256 amount) public balances;`

This is the internal accounting ledger. It does not guarantee that the contract still holds the Ether it promises. After the attack, you can have a state where `balances[Alice] == 5 ether` while `address(this).balance == 0`.

### `deposit()`

This function is safe on its own:

- it rejects zero-value deposits;
- it increases the internal balance;
- it emits an event.

The vulnerability is not in the deposit path. It is in the withdrawal path.

### `withdraw(uint256 amount)`

The critical lines are:

```solidity
uint256 currentBalance = balances[msg.sender];
require(currentBalance >= amount, "Insufficient balance");
(bool success, ) = payable(msg.sender).call{value: amount}("");
balances[msg.sender] = currentBalance - amount;
```

Breakdown:

- the first line captures a balance snapshot in memory;
- the second line validates that snapshot;
- the third line transfers control to untrusted code;
- the fourth line writes a stale result back to storage.

From an invariant perspective, the logic should be reversed: once the contract has decided that a withdrawal is valid, its internal accounting must already reflect the post-withdrawal state before any external interaction happens.

## Line-by-Line Analysis of `Attack.sol`

### `target`

This stores the address of the vulnerable vault. The attacker contract always knows where to reenter.

### `attackChunk`

This is the amount withdrawn in each recursive iteration. The exploit repeatedly pulls the same chunk.

### `attack()`

This function does three things:

1. accepts seed capital;
2. deposits it into the vault;
3. triggers the first `withdraw`.

The first `withdraw` does not drain the contract by itself. It only opens the door for reentrancy via `receive()`.

### `receive()`

This is the core of the exploit. When the vault sends Ether to the attacker contract, `receive()` is automatically executed by the EVM. Inside it, the logic is:

```solidity
if (address(target).balance >= attackChunk) {
    target.withdraw(attackChunk);
}
```

Each incoming payment immediately triggers another withdrawal from the vault. As long as the vault has Ether and the internal state has not been safely finalized, the loop continues.

### `withdrawLoot()`

After the exploit chain is complete, the stolen Ether sits on the attacker contract. This function forwards it to the operator, meaning the attacker’s EOA.

## Line-by-Line Analysis of `Fixed.sol`

The secure version uses two defense layers.

### 1. Checks-Effects-Interactions

The main idea is simple: checks first, then state changes, then external interactions.

In `FixedVault.withdraw()` the order is:

```solidity
require(amount > 0, "Amount must be greater than zero");
require(balances[msg.sender] >= amount, "Insufficient balance");
balances[msg.sender] -= amount;
(bool success, ) = payable(msg.sender).call{value: amount}("");
require(success, "Ether transfer failed");
```

If the attacker tries to reenter from `receive()`, the second call sees the updated balance.

### 2. Custom `nonReentrant`

The contract also uses a simple custom lock:

```solidity
require(!locked, "ReentrancyGuard: reentrant call");
locked = true;
_;
locked = false;
```

This does not replace CEI. It reinforces it. If a later refactor accidentally weakens the function structure, the guard still provides an additional protective layer.

## Why the Fixed-Version Attack Test Reverts with `Ether transfer failed`

This is an important educational detail. When `FixedVault` sends Ether to the attacker contract, `receive()` executes. Inside `receive()`, the attacker tries to call `withdraw` again. But the second call is blocked by the reentrancy guard or by the already updated state. That internal attempt reverts, so the low-level `call` returns `success == false`. `FixedVault` then hits `require(success, "Ether transfer failed")` and reverts the entire transaction.

The result is:

- the attacker’s deposit does not persist;
- honest users’ funds remain safe;
- the vault does not end up in a partially corrupted state.

## Real-World Example: The DAO Hack

The most famous example of reentrancy is the 2016 exploit of The DAO. The DAO was one of the earliest large-scale experiments in decentralized governance and accumulated a massive amount of Ether. In its split and withdrawal logic, an attacker discovered a reentrancy opportunity: the contract sent funds before its internal state was updated correctly. That enabled repeated withdrawals inside a single logical flow.

The consequences were enormous:

- millions of dollars worth of ETH were drained;
- trust in the Ethereum ecosystem was severely damaged;
- the community ultimately executed a hard fork, leading to Ethereum and Ethereum Classic.

Why this case still matters:

- it proved that “code is law” does not protect you from flawed logic;
- it made reentrancy a mandatory topic in smart-contract audits;
- it permanently changed security culture in Ethereum development.

In modern audits, any external call inside a function that changes balances, permissions, debt, shares, positions, or reward state is treated as a potential reentrancy surface.

## Remediation Strategies

### Checks-Effects-Interactions

This is the foundational defense pattern:

1. Validate preconditions.
2. Update internal state.
3. Interact with external parties only afterward.

For withdrawal flows, this is usually the minimum acceptable standard.

### Reentrancy Guard

A guard is especially useful when:

- the logic is complex;
- multiple functions share the same critical state;
- future refactors may accidentally break CEI;
- cross-function reentrancy is possible.

A guard should not be the only defense when the architecture itself is fragile. It is a safety net, not an excuse for poor state ordering.

### Pull Over Push

Whenever possible, avoid aggressive push-based payment flows. When a contract actively sends value to many recipients, the attack surface grows. A pull model, where users claim previously calculated funds themselves, is often safer and easier to reason about.

### Treat External Calls as Untrusted

Every external interaction should be treated as untrusted:

- a token contract may be malicious;
- a recipient may be a contract instead of an EOA;
- an interface may hide unexpected logic;
- a callback may invoke any public function on your contract.

## Best Practices

- Always apply Checks-Effects-Interactions in functions that combine sensitive state changes with external calls.
- Use `ReentrancyGuard` or a custom lock when the flow genuinely needs additional protection.
- Analyze not only single-function reentrancy, but also cross-function reentrancy. For example, `deposit`, `claim`, `withdraw`, and `liquidate` may all affect the same invariants.
- Separate accounting logic from external integrations whenever possible.
- Verify that the post-state preserves invariants even under malicious callbacks.
- Write tests with attacker contracts, not only EOAs.
- Do not rely on `transfer` as a modern security mechanism.
- Check whether token hooks such as ERC777 or callback-style architectures create hidden reentrancy surfaces.

## Common Developer Mistakes

### Mistake 1: “I update the balance somewhere in the function, so I’m safe”

It is not enough to update the balance eventually. What matters is when that update happens. If an external call already took place, the invariant may already be broken.

### Mistake 2: “My recipient is a user, not a contract”

You cannot safely assume that an address is always an EOA. It may be a contract, a proxy, or a future deployment target in CREATE2-like scenarios.

### Mistake 3: “I use OpenZeppelin, so everything is automatically safe”

Libraries help, but they do not replace architectural thinking. If the business logic around `nonReentrant` is flawed, the vulnerability can still manifest in another form.

### Mistake 4: “Reentrancy only happens when sending Ether”

No. It can happen with token transfers, external protocol calls, callback interfaces, hook systems, and seemingly harmless contract-to-contract interactions.

### Mistake 5: “If my test passes with a normal account, withdraw is safe”

EOA-only tests almost never catch reentrancy. You need a dedicated attacker contract implementing `receive()` or `fallback()` and explicitly reentering the target.

## How to Read the Tests in This Module

The file `test/reentrancy.attack.test.js` builds a realistic scenario:

- there are two honest depositors;
- there is a separate attacker operator;
- the attacker uses a contract, not an EOA;
- after the exploit, the test checks not only that the vault is empty, but also that the accounting still incorrectly promises funds to honest users.

The file `test/reentrancy.fix.test.js` verifies two things:

- the attack against `FixedVault` fails;
- honest users can still withdraw funds normally.

This is a core secure-development principle: it is not enough to stop the exploit. You must also prove that legitimate functionality still works.

## Why This Module Is Closer to a Real Audit Than a Typical Tutorial

Many reentrancy tutorials are too simplified:

- one user only;
- one withdrawal path;
- almost no post-attack state validation;
- no explanation of why storage and Ether balance diverge;
- no test proving that the mitigation preserves normal behavior.

In an audit, we care not only about the exploit, but about its consequences:

- what happens to accounting;
- whether invariants can still be trusted;
- whether the fix breaks user functionality;
- whether the team is left with false confidence.

That is why this module uses a vault-style model, two honest participants, a dedicated attacker contract, and two separate test files.

## Conclusion

Reentrancy is not just “someone used `receive()` and stole money.” It is a class of state-management failures. It appears when a developer forgets that an external call hands control to potentially hostile code before the sensitive logic is truly complete.

The correct mental model is:

- storage must already reflect a safe state before any external call;
- every external call can execute arbitrary code;
- every callback must be treated as hostile by default;
- protection should be layered: architecture, CEI, guards, and adversarial tests.

If you build the habit of asking, “What happens if control leaves the contract right here?”, you are already thinking like a security engineer. That is exactly the point of the Solidity Security Lab.
