<p align="center">
  <img src="../../../public/SCSL_banner.png" alt="SCSL banner" width="100%" style="max-height: 220px; object-fit: cover; object-position: center;" />
</p>

# FLASH LOANS: Full Educational Module on Flash-Loan-Enabled Price Manipulation in Solidity

## Introduction

Flash loans are one of the most powerful and misunderstood mechanics in DeFi. At a basic level, a flash loan allows a borrower to access a large amount of capital with no upfront collateral, as long as the borrowed amount is returned by the end of the same transaction. This creates an unusual and highly adversarial environment for smart-contract design, because assumptions that feel safe under “normal capital constraints” can become catastrophically false when an attacker can temporarily control a huge amount of liquidity.

The common beginner mistake is to think that flash loans are the vulnerability. They are not. A flash loan is just a tool. The real vulnerability is usually something else:

- a manipulable price oracle;
- a fragile collateral valuation model;
- a bad accounting assumption;
- insufficient slippage protection;
- a protocol that trusts one transaction’s instantaneous state too much.

This module demonstrates one of the most important and historically relevant flash-loan attack patterns: spot-price oracle manipulation. A lending protocol accepts token collateral and lets users borrow ETH against it. Instead of using a robust oracle, it values the collateral using the instantaneous spot price from a low-liquidity AMM. An attacker uses a flash loan of ETH to buy tokens from that AMM, pumping the token price inside the same transaction. The lending protocol then sees an inflated collateral value and lets the attacker borrow much more ETH than the collateral is truly worth.

This module includes:

- a flash-loan pool;
- a low-liquidity ETH/token AMM;
- a vulnerable lending vault that trusts the AMM spot price;
- an attacker contract that performs the full atomic exploit;
- a fixed lending vault that uses a trusted oracle instead of manipulable spot pricing;
- tests that prove both the exploit and the mitigation.

The key lesson is simple: **flash loans do not create bugs, but they amplify weak assumptions into fully weaponized exploits.**

## What a Flash Loan Is

A flash loan is a loan that exists only within one transaction.

Typical flash-loan flow:

1. Borrow assets from a lender.
2. Use those assets for some on-chain operations.
3. Repay the lender before the transaction ends.
4. If repayment fails, the whole transaction reverts.

The reason this is powerful is that the borrower does not need permanent capital. If a protocol can be manipulated using large temporary liquidity, flash loans let an attacker access that liquidity on demand.

This means security reviewers must ask:

- what if the attacker had 10x, 100x, or 1000x more capital for one transaction?
- what assumptions break under that condition?

## Why Flash Loans Matter for Security

Flash loans do not magically violate invariants. They exploit protocols whose invariants were too weak to begin with.

Common flash-loan-assisted exploit families include:

- price-oracle manipulation;
- governance vote borrowing;
- collateral inflation or deflation;
- liquidation abuse;
- pool share manipulation;
- reward distribution abuse;
- accounting systems that assume liquidity cannot change atomically.

The unifying lesson is this: if your protocol relies on an external state that can be moved significantly inside one transaction, then flash-loan capital can weaponize that dependency.

## The Vulnerable Architecture in This Module

This module uses four components:

1. `FlashLoanEtherLender`
2. `FlashLoanSpotAMM`
3. `SpotOracleLendingVault`
4. `FlashLoanPriceManipulationAttacker`

### 1. Flash-loan pool

The flash-loan pool lends ETH and requires it to be returned by the end of the callback.

### 2. Spot-price AMM

The AMM provides a current token price in ETH based on its reserve ratio:

```solidity
price = ethReserve / tokenReserve
```

This spot price is intentionally easy to manipulate because the AMM is shallow.

### 3. Vulnerable lending vault

The lending vault accepts the token as collateral and lets borrowers take out ETH loans up to 75% LTV. But instead of using a trusted oracle or time-weighted price, it values collateral using the AMM’s instantaneous spot price:

```solidity
uint256 priceEthPerToken = oracleAmm.spotPriceEthPerToken();
```

That is the real vulnerability.

### 4. Attacker contract

The attacker borrows ETH via flash loan, buys tokens from the AMM to raise the spot price, deposits those now-overvalued tokens as collateral, borrows ETH from the vulnerable vault, repays the flash loan, and keeps the remainder.

## Step-by-Step Attack Walkthrough

The tests use realistic numbers:

- the flash lender has 120 ETH;
- the AMM starts with 100 ETH and 1000 tokens;
- the lending vault holds 150 ETH;
- the lending vault uses a 75% LTV ratio;
- the attacker flash-loans 80 ETH.

Now the exploit happens:

1. The attacker takes an 80 ETH flash loan.
2. The attacker uses that 80 ETH to buy tokens from the AMM.
3. Because the AMM is shallow, this dramatically changes the reserve ratio:
   - ETH reserve rises
   - token reserve falls
4. The spot price of the token in ETH becomes much higher.
5. The attacker deposits the purchased tokens as collateral into the lending vault.
6. The lending vault values those tokens using the manipulated AMM spot price.
7. The vault concludes that the attacker’s collateral is worth much more ETH than it really should be.
8. The attacker borrows 108 ETH from the lending vault.
9. The attacker repays the 80 ETH flash loan.
10. The attacker keeps the remaining 28 ETH as profit.

All of this happens atomically in one transaction.

The flash lender ends whole. The AMM ends manipulated. The lending vault is the victim.

## Why the Math Works

Initial AMM reserves:

- 100 ETH
- 1000 tokens

Initial spot price:

- `100 / 1000 = 0.1 ETH per token`

The attacker spends 80 ETH to buy tokens.

Using the simple quote in this educational AMM:

```text
tokensOut = 80 * 1000 / (100 + 80) = 444.44 tokens
```

New AMM reserves become approximately:

- 180 ETH
- 555.56 tokens

New spot price:

- `180 / 555.56 ≈ 0.324 ETH per token`

So the attacker’s 444.44 tokens are now valued by the lending vault at roughly:

- `444.44 * 0.324 ≈ 144 ETH`

At 75% LTV, the protocol allows borrowing approximately:

- `144 * 0.75 = 108 ETH`

That is enough to:

- repay the 80 ETH flash loan;
- keep 28 ETH profit.

The exact exploitability depends on liquidity and LTV, but the pattern is robust: the vault trusts an immediately manipulable price.

## EVM-Level Execution Flow

This attack is a perfect example of why atomic state matters.

Inside one transaction:

1. The flash lender transfers ETH to the attacker contract.
2. The attacker contract buys tokens from the AMM.
3. The AMM state changes instantly.
4. The lending vault reads the manipulated AMM state in the same transaction.
5. The attacker borrows against that manipulated valuation.
6. The attacker repays the flash loan before the transaction ends.

No external liquidation, no waiting period, no “later correction” matters during that transaction. The vulnerable vault reads a bad price at exactly the wrong time and acts on it immediately.

This is why protocols that rely on spot prices are so vulnerable to flash loans: atomic state changes make short-lived manipulation fully usable.

## Line-by-Line Analysis of `Vulnerable.sol`

### `FlashLoanEtherLender`

The flash-loan pool itself is not the vulnerability. Its logic is simple:

```solidity
IFlashLoanEtherReceiver(msg.sender).onFlashLoan{value: amount}(amount);
require(address(this).balance >= balanceBefore, "Flash loan not repaid");
```

This pool behaves correctly. It just provides temporary capital.

### `FlashLoanSpotAMM`

The AMM is also not “buggy” in the usual sense. It provides:

- liquidity;
- token purchases;
- spot price derived from reserves.

The important issue is not that the AMM price exists. The issue is that another protocol treats that spot price as a trusted collateral oracle.

### `SpotOracleLendingVault`

This is the real vulnerability surface.

The critical function is:

```solidity
function collateralValueInEth(address borrower) public view returns (uint256) {
    uint256 priceEthPerToken = oracleAmm.spotPriceEthPerToken();
    return (collateralBalance[borrower] * priceEthPerToken) / 1e18;
}
```

This means collateral valuation depends entirely on the AMM’s current reserve ratio.

Then:

```solidity
require(amount <= maximumBorrow(msg.sender), "Borrow amount too high");
```

If the price is manipulated upward, `maximumBorrow()` becomes artificially large.

That is the exploit.

## Line-by-Line Analysis of `Attack.sol`

### `attack(uint256 flashLoanAmount)`

This starts the exploit by requesting a flash loan.

### `onFlashLoan(uint256 amount)`

This is the core callback. It does four critical things in sequence:

1. buys tokens to manipulate the AMM price;
2. deposits those tokens as collateral;
3. borrows as much ETH as the vulnerable vault allows;
4. repays the flash loan.

Each of those steps is simple alone. Together, they weaponize the protocol’s oracle assumption.

### Why the attack succeeds

The attacker never needs permanent 80 ETH capital. That is why flash loans are so powerful in practice. The protocol is being attacked by a short-lived but enormous balance spike.

## The Fixed Contract: `SafeOracleLendingVault`

The fixed version changes the oracle model completely.

Instead of trusting the AMM spot price, it reads collateral value from:

```solidity
TrustedPriceOracle
```

That oracle returns a stable preconfigured value:

- `0.1 ETH per token`

Now the AMM can still be manipulated, but the lending vault does not care. Its collateral valuation is no longer tied to the attacker’s temporary trading activity.

The fixed collateral value function becomes:

```solidity
uint256 priceEthPerToken = trustedOracle.getPriceEthPerToken();
```

That decouples borrowing limits from in-transaction AMM manipulation.

## Why the Fixed Version Stops the Attack

Suppose the attacker repeats the same flash-loan sequence:

1. borrow 80 ETH;
2. buy tokens and inflate the AMM spot price;
3. deposit the acquired tokens as collateral;
4. try to borrow ETH.

The crucial difference is:

- the safe vault still values the collateral at the trusted oracle price of `0.1 ETH per token`.

So even after the AMM manipulation, the attacker’s purchased tokens are worth only about:

- `444.44 * 0.1 = 44.44 ETH`

At 75% LTV, the maximum borrow is only about:

- `33.33 ETH`

That is nowhere near enough to repay the 80 ETH flash loan. As a result, the attacker cannot restore the flash lender’s balance, and the whole transaction reverts with:

- `Flash loan not repaid`

That is the correct outcome.

## Real-World Context: Why Flash-Loan Oracle Attacks Matter

This pattern is one of the defining attack classes in DeFi history. Many real systems were exploited because they trusted:

- AMM spot prices;
- single-block reserve states;
- manipulable on-chain views without time weighting;
- collateral valuations that could be changed atomically.

The underlying design mistake is almost always the same:

- the protocol assumes the observed market state is trustworthy enough for immediate lending, settlement, or reward calculations;
- the attacker proves it is not.

This is why modern lending protocols prefer:

- Chainlink or similar external oracles;
- time-weighted average prices (TWAP);
- multi-source aggregation;
- staleness checks;
- circuit breakers and liquidity sanity checks.

## Remediation Strategies

### Do Not Use Manipulable Spot Prices for Lending Decisions

If a price can be moved significantly inside one transaction, it should not directly determine collateral value for borrowing.

### Use Trusted or Robust Oracles

Safer options include:

- decentralized oracle networks;
- TWAP oracles with sufficient observation windows;
- multi-source median or median-like designs;
- explicit governance-controlled trusted oracles for lower-complexity systems.

### Add Borrowing Friction

Depending on the protocol, mitigations can include:

- caps;
- isolation modes;
- collateral factors that reflect liquidity risk;
- delayed activation of newly deposited collateral;
- sanity checks against multiple price sources.

### Design for Atomic Adversaries

Assume the attacker can:

- borrow huge capital;
- move state across multiple protocols;
- return capital in the same transaction;
- exploit any instantaneously trusted valuation.

## Best Practices

- Never use raw AMM spot price as the sole oracle for lending or liquidation logic.
- Assume large temporary capital is available through flash loans.
- Use trusted or time-weighted oracle designs for collateral valuation.
- Test atomic price manipulation explicitly.
- Separate market-execution logic from risk-critical valuation logic.
- Add caps and conservative collateral factors for volatile or low-liquidity assets.
- Audit every place where one-transaction price changes affect borrowing power.
- Remember that “read-only” price functions can still be a critical security boundary.

## Common Developer Mistakes

### Mistake 1: “The AMM price is on-chain, so it must be trustworthy”

On-chain visibility does not make a value manipulation-resistant. AMM spot price is often the easiest price to manipulate in a flash-loan setting.

### Mistake 2: “The attacker would need too much capital”

That assumption is exactly what flash loans invalidate.

### Mistake 3: “The manipulation only lasts one transaction, so it is harmless”

If your protocol acts on that manipulated state inside the same transaction, one transaction is all the attacker needs.

### Mistake 4: “Using a lower LTV solves the oracle problem”

A lower LTV can reduce damage, but if the oracle is bad enough, even conservative LTV may still be exploitable.

### Mistake 5: “Only lending protocols need to care about flash loans”

No. Any system that depends on temporarily manipulable state can become flash-loan-sensitive.

## How to Read the Tests in This Module

The vulnerable tests show:

- a flash lender with ETH liquidity;
- a shallow AMM used as the spot oracle source;
- a lending vault funded with borrowable ETH;
- the attacker taking an 80 ETH flash loan;
- the AMM price being pumped;
- the lending vault being tricked into overvaluing collateral;
- the flash loan being repaid;
- the attacker keeping 28 ETH profit.

The fixed tests show:

- the same atomic attempt now fails because the safe vault ignores the manipulated AMM price;
- the flash loan cannot be repaid, so the transaction reverts;
- an honest borrower can still deposit real collateral and borrow within a safe oracle limit.

This is exactly the educational contrast we want: same capital, same manipulative flow, different oracle assumption, completely different security outcome.

## Why This Module Feels Like a Real Audit Case

Many flash-loan tutorials stop at saying “flash loans are dangerous” or “use Chainlink.” That is not enough. Real audits focus on specific questions:

- what state is read after the attacker can move it?
- can that state be manipulated atomically?
- does that manipulated state affect collateral, pricing, or reward logic?
- does the protocol rely on spot values where it should rely on robust valuation?

This module is built around those practical questions. The exploit flow is not contrived. It is structurally similar to many real DeFi failures.

## Conclusion

Flash loans are not exploits by themselves. They are force multipliers for weak protocol assumptions. If your system trusts a value that can be moved within one transaction, flash-loan liquidity can turn that trust into immediate loss.

The key lessons from this module are:

- flash loans remove capital constraints from the attacker model;
- spot prices are not safe collateral oracles;
- lending decisions must rely on robust valuation, not manipulable instantaneous state.

If you build the habit of asking, “What if the attacker could move this state dramatically and revert the capital source by the end of the same transaction?”, you are thinking like a smart-contract security engineer. That is exactly the mindset this lab is designed to build.
