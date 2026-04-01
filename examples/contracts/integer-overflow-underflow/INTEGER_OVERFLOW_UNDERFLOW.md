<p align="center">
  <img src="../../../public/SCSL_banner.png" alt="SCSL banner" width="100%" style="max-height: 220px; object-fit: cover; object-position: center;" />
</p>

# INTEGER OVERFLOW UNDERFLOW: Full Educational Module on Arithmetic Vulnerabilities in Solidity

## Introduction

Integer overflow and underflow are among the most important topics in Solidity security history. Before Solidity 0.8, arithmetic on unsigned integers wrapped silently. If a value exceeded the maximum representable number, it would roll over back to zero. If a subtraction went below zero, it would wrap around to a huge `uint256` value. This behavior led to many vulnerabilities, because developers often assumed arithmetic would fail safely when it actually did not.

Starting with Solidity 0.8, checked arithmetic became the default. That was a major security improvement. Today, many junior developers hear “overflow and underflow were fixed in Solidity 0.8” and conclude the topic no longer matters. That conclusion is dangerous. Arithmetic bugs still matter for three reasons:

- teams still maintain older contracts and forks;
- developers use `unchecked` blocks for gas optimization or convenience;
- arithmetic is deeply connected to accounting, and broken accounting still breaks real protocols.

This module is built around a modern and realistic version of the problem: a Solidity 0.8 Ether vault that reintroduces underflow risk by using `unchecked` incorrectly. The bug is not “the compiler forgot to protect me.” The bug is “the developer bypassed the compiler’s protection without restoring the missing safety checks.”

This module includes:

- a vulnerable Ether vault with unchecked arithmetic in credit accounting;
- an attacker contract that drains the vault without making a deposit;
- a fixed version that restores explicit balance checks;
- tests proving both the exploit and the mitigation;
- detailed explanations of why the bug exists and how to reason about it.

The goal is not just to repeat historical trivia about older Solidity versions. The goal is to teach a modern security lesson: **unchecked arithmetic is safe only when the developer has already proved the operation cannot overflow or underflow.**

## What Overflow and Underflow Mean

An integer type such as `uint256` has a finite range:

- minimum value: `0`
- maximum value: `2^256 - 1`

Two failure modes are classically important:

### Overflow

Overflow happens when an arithmetic operation exceeds the maximum representable value.

Example in an old unchecked model:

```solidity
uint256 x = type(uint256).max;
x = x + 1;
```

Instead of failing, `x` would wrap to `0`.

### Underflow

Underflow happens when an arithmetic operation goes below the minimum representable value.

Example in an old unchecked model:

```solidity
uint256 x = 0;
x = x - 1;
```

Instead of failing, `x` would wrap to `2^256 - 1`.

That second behavior is especially dangerous for accounting. If a contract believes it just subtracted from zero and produced a huge balance, privilege checks, withdrawal limits, debt tracking, or token balances may all become corrupted.

## Why This Still Matters in Solidity 0.8+

Solidity 0.8 introduced checked arithmetic by default. That means:

- `x + 1` reverts on overflow;
- `x - 1` reverts on underflow.

That default is excellent, but it is not absolute. Developers can still write:

```solidity
unchecked {
    x -= amount;
}
```

Inside `unchecked`, Solidity intentionally returns to wrapping arithmetic. That can be correct and safe in some tightly controlled situations, but only if the code has already proved the operation is valid.

For example, this can be safe:

```solidity
require(balance >= amount, "Insufficient balance");
unchecked {
    balance -= amount;
}
```

This is not safe:

```solidity
unchecked {
    balance -= amount;
}
```

without first proving `balance >= amount`.

This module demonstrates exactly that mistake.

## The Vulnerable Contract: `UncheckedRewardVault`

The vulnerable contract accepts Ether deposits and mints internal redeemable credits. Users can later redeem credits back into Ether.

The accounting model is intentionally simple:

- depositing Ether increases `rewardCredits[msg.sender]`;
- redeeming credits transfers Ether back to the caller.

The dangerous logic is in the redemption flow:

```solidity
require(address(this).balance >= weiAmount, "Vault lacks Ether");

unchecked {
    rewardCredits[msg.sender] -= creditAmount;
}

(bool success, ) = payable(msg.sender).call{value: weiAmount}("");
```

The problem is subtle but critical:

- the contract checks that the vault has enough Ether;
- it does **not** check that the caller has enough credits;
- then it subtracts inside `unchecked`.

If the caller has zero credits and asks to redeem a huge `creditAmount`, the subtraction underflows and wraps to a massive `uint256` value. The Ether transfer still succeeds as long as the vault itself has enough Ether.

That means an attacker can drain honest users’ deposits without owning any redeemable credits at all.

## Step-by-Step Attack Walkthrough

The tests use a realistic scenario:

- Alice deposits 3 ETH;
- Bob deposits 4 ETH;
- the vault now holds 7 ETH;
- the attacker deploys an exploit contract but never deposits anything.

Now the exploit begins:

1. The attacker contract calls `vaultBalance()` and sees that the vault holds 7 ETH.
2. It computes a fake `creditAmount` equal to `7 ether * CREDIT_PER_WEI`.
3. It calls `redeem(fakeCreditAmount)`.
4. The vulnerable vault checks that:
   - `creditAmount > 0`
   - the resulting `weiAmount` is non-zero
   - the vault has enough Ether
5. The vault never checks `rewardCredits[msg.sender] >= creditAmount`.
6. Inside `unchecked`, the subtraction runs on a zero balance.
7. The attacker’s internal credit balance wraps to a massive `uint256`.
8. The vault transfers 7 ETH to the attacker contract.
9. Honest users still appear to own credits in storage, but the Ether backing them is gone.

This is a classic accounting failure: the internal ledger and actual funds diverge because arithmetic safety was bypassed incorrectly.

## Why the Attack Works at the EVM Level

At the EVM level, subtraction on `uint256` inside `unchecked` behaves modulo `2^256`.

That means:

```text
0 - N  mod 2^256  =  2^256 - N
```

If `rewardCredits[attacker] == 0` and the contract executes:

```solidity
unchecked {
    rewardCredits[attacker] -= forgedCreditAmount;
}
```

the result is not an error. It becomes a huge wrapped value.

The contract then sends Ether based on `creditAmount / CREDIT_PER_WEI`, not based on whether the attacker legitimately earned those credits. Because the vault’s balance check only verifies available Ether, not credit ownership, the transfer succeeds.

The core failure is therefore not “underflow exists.” The core failure is:

- the accounting precondition was omitted;
- `unchecked` disabled the safety mechanism that would have exposed that omission.

## Line-by-Line Analysis of `Vulnerable.sol`

### `uint256 public constant CREDIT_PER_WEI = 1e18;`

This defines the exchange rate between credits and wei. The exact rate is not the security issue. It simply makes the internal accounting explicit for the educational model.

### `mapping(address account => uint256 amount) public rewardCredits;`

This mapping stores each user’s redeemable internal balance. In a real protocol, this could represent:

- vault shares;
- points;
- coupon entitlements;
- redeemable debt claims;
- staking receipts.

If this mapping becomes corrupted, every balance-related guarantee becomes suspect.

### `deposit()`

This function is straightforward:

- it rejects zero deposits;
- it computes credits;
- it adds them to the caller’s balance;
- it emits an event.

The deposit path is not the vulnerable one in this module.

### `redeem(uint256 creditAmount)`

This is the critical flow.

The function does some correct things:

- it rejects zero credit redemptions;
- it ensures the conversion produces a non-zero Ether amount;
- it checks the vault’s actual Ether balance.

But it misses the most important check:

```solidity
require(rewardCredits[msg.sender] >= creditAmount, "Insufficient credits");
```

Without that line, the `unchecked` subtraction becomes dangerous:

```solidity
unchecked {
    rewardCredits[msg.sender] -= creditAmount;
}
```

This is the exact source of the exploit.

## Line-by-Line Analysis of `Attack.sol`

### `vaultBalance()`

The attacker first reads the vault’s current Ether balance. This is realistic. Many exploits are adaptive: attackers inspect the live state before deciding how much to extract.

### `forgedCreditAmount = drainAmount * CREDIT_PER_WEI`

The exploit chooses a fake number of credits corresponding to the full vault balance. The attacker is essentially saying, “Pretend I own enough credits to redeem everything.”

### `target.redeem(forgedCreditAmount)`

This is where the exploit executes. Because the vulnerable vault validates Ether availability but not the attacker’s actual credit ownership, the forged redemption works.

### `withdrawLoot()`

After the exploit, the Ether sits inside the attacker contract. This function forwards it to the attacker operator’s EOA.

## The Fixed Contract: `SafeRewardVault`

The secure version restores the missing accounting guard:

```solidity
require(rewardCredits[msg.sender] >= creditAmount, "Insufficient credits");
```

Then it uses normal checked subtraction:

```solidity
rewardCredits[msg.sender] -= creditAmount;
```

This ensures that:

- only real credit holders can redeem;
- arithmetic safety is enforced by the compiler;
- the internal ledger remains consistent with entitlement.

The fixed contract also follows a better state-update order:

1. validate the input;
2. validate credit ownership;
3. reduce credits;
4. send Ether.

That sequence preserves accounting integrity.

## Why the Fixed Version Stops the Attack

When the attacker contract calls `redeem(forgedCreditAmount)` against `SafeRewardVault`, the flow changes immediately:

1. The contract computes `weiAmount`.
2. The contract checks:

```solidity
require(rewardCredits[msg.sender] >= creditAmount, "Insufficient credits");
```

3. Because the attacker never deposited anything, `rewardCredits[msg.sender] == 0`.
4. The call reverts.
5. The vault balance stays intact.

This is the exact behavior we want. Authorization over value redemption must be based on the caller’s actual economic entitlement, not just on the vault’s current liquidity.

## Historical Context: Why Arithmetic Bugs Became Famous

Before Solidity 0.8, arithmetic issues were extremely common. Many token contracts, vaults, and accounting systems were written under assumptions that looked mathematically obvious but were not enforced by the language.

One of the best-known broad lessons from that era was that token balances, supply math, and allowance math could be catastrophically wrong if arithmetic wrapped silently. Even when a specific historical exploit involved different business logic, the pattern was the same:

- developers assumed arithmetic would behave like “normal math”;
- the EVM behaved like modular arithmetic;
- the mismatch created exploitable state corruption.

Solidity 0.8 solved a large part of that problem by changing the default behavior, but it did not eliminate the need for careful reasoning. The moment a team uses `unchecked`, performs custom math, compresses storage values, or ports older code, arithmetic risk comes back.

## Remediation Strategies

### Avoid `unchecked` Unless You Have a Proven Invariant

`unchecked` is not inherently bad. It is a tool. But it is only safe when the surrounding logic already proves the arithmetic cannot overflow or underflow.

### Always Validate Ownership Before Burning or Spending Balances

Any function that decreases balances, shares, allowances, or debt positions should explicitly prove that the caller has enough available value first.

### Keep Accounting and Liquidity Checks Separate

It is not enough to ask:

- does the vault have enough Ether?

You must also ask:

- is the caller entitled to receive that Ether?

Both conditions matter.

### Prefer Simpler Arithmetic Over Micro-Optimized Arithmetic

Many bugs enter code when teams chase tiny gas savings at the expense of readability and invariants. A small optimization is never worth a broken ledger.

### Use Adversarial Tests

Do not only test happy paths. Test:

- zero balances;
- edge values;
- forged redemption amounts;
- repeated calls;
- large accounting values;
- malicious contracts.

## Best Practices

- Use checked arithmetic by default in Solidity 0.8+.
- Add explicit precondition checks before any subtraction on balances or entitlements.
- Use `unchecked` only when the invariant is already proven and easy to audit.
- Keep internal accounting logic minimal and well documented.
- Test both economic correctness and arithmetic safety.
- Review every place where balances, shares, debt, supply, or rewards are incremented or decremented.
- Treat ledger corruption as a critical financial vulnerability.
- Prefer clear code over premature gas optimization in accounting paths.

## Common Developer Mistakes

### Mistake 1: “Solidity 0.8 fixed this forever”

No. Solidity 0.8 fixed unchecked wrapping by default. It did not protect contracts that manually opt back into wrapping arithmetic through `unchecked`.

### Mistake 2: “If the vault has enough Ether, the redemption must be valid”

This confuses liquidity with entitlement. A vault having funds does not mean the caller has earned the right to receive them.

### Mistake 3: “`unchecked` is just a harmless gas optimization”

It is only harmless when the necessary invariants have already been enforced. Otherwise it removes one of the most valuable built-in safety features in modern Solidity.

### Mistake 4: “Arithmetic bugs only matter in tokens”

No. They matter in vaults, reward systems, lending positions, staking ledgers, governance accounting, vesting systems, and many other places.

### Mistake 5: “If one balance becomes weird, that is just a display bug”

Broken accounting is rarely “just UI.” In financial contracts, incorrect state usually means incorrect asset movement, broken limits, or future exploitable paths.

## How to Read the Tests in This Module

The vulnerable tests demonstrate:

- honest users funding a live vault;
- the attacker making no deposit at all;
- the attacker forging a redemption amount;
- unchecked underflow corrupting the internal balance;
- the vault being fully drained.

The fixed tests demonstrate:

- the same forged redemption now reverts;
- honest-user balances stay intact;
- legitimate depositors can still redeem their own credits normally.

This is exactly what we want from a good mitigation: block the exploit while preserving the intended product behavior.

## Why This Module Feels Like a Real Audit Case

Many arithmetic tutorials stop at trivial snippets like:

```solidity
uint8 x = 255;
x++;
```

That explains the concept, but not the real risk. In real audits, the question is not “can a number wrap?” The real question is:

- what financial invariant depends on this arithmetic?
- can a wrapped value create fake entitlement?
- can underflow or overflow bypass a limit or cap?
- can ledger corruption turn into asset theft?

This module is built around those more practical questions. The vulnerable code is not just mathematically wrong. It is economically wrong.

## Conclusion

Integer overflow and underflow are not obsolete topics. They are still deeply relevant wherever developers bypass safe arithmetic or fail to prove accounting invariants.

The key lesson from this module is:

- arithmetic safety and accounting safety are inseparable;
- `unchecked` should be used only when correctness is already proven;
- a missing balance check before subtraction can turn into direct theft.

If you train yourself to ask, “What invariant makes this subtraction safe, and where is that invariant enforced?”, you are thinking like a smart-contract security engineer. That is exactly the skill this lab is meant to build.
