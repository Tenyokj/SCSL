<p align="center">
  <img src="../../../public/SCSL_banner.png" alt="SCSL banner" width="100%" style="max-height: 220px; object-fit: cover; object-position: center;" />
</p>

# FRONT RUNNING MEV: Full Educational Module on Transaction Ordering Abuse in Solidity

## Introduction

Front-running and MEV are among the most important real-world security topics in Ethereum. Unlike many classic smart-contract bugs, front-running is not always about breaking a function’s correctness. Often the contract does exactly what it was programmed to do. The problem is that it does so in a public mempool environment where transaction ordering is economically adversarial.

On Ethereum and similar networks, users broadcast transactions before they are finalized. That means other participants can observe pending intents and react before those intents are included on-chain. Validators, builders, searchers, and sophisticated traders can profit from this visibility by reordering, inserting, or suppressing transactions.

This is the broad world of MEV, or Maximal Extractable Value. A protocol may be mathematically correct and still expose users to severe economic loss if it ignores adversarial transaction ordering.

This module demonstrates a classic and very practical case: an ETH-to-token swap function that does not enforce `minOut`. A user observes a quote and submits a trade. Before it executes, an attacker buys first, moving the price against the victim. Because the victim transaction contains no slippage protection, it still executes, but at a much worse price than expected.

This module includes:

- a vulnerable AMM-style swap contract;
- an attacker contract that front-runs by moving the price first;
- a fixed AMM that adds `minTokensOut` and `deadline`;
- tests proving both the exploit and the mitigation;
- a detailed explanation of why transaction ordering matters in smart-contract security.

The key lesson is simple: **if your protocol allows economically sensitive execution without user-defined bounds, mempool observers can turn normal user intent into guaranteed loss.**

## What Front-Running Means

Front-running happens when someone sees a pending transaction and inserts their own transaction before it in order to benefit from the victim’s intent.

Common front-running targets include:

- swaps;
- NFT mints;
- liquidation calls;
- arbitrage opportunities;
- governance actions;
- auctions;
- order settlement;
- reward claims.

In many cases, the attacker does not need a bug in the traditional sense. They only need:

- visibility into the victim’s pending action;
- a protocol state that changes with ordering;
- a way to profit from moving first.

## What MEV Means

MEV stands for Maximal Extractable Value. It describes the value that can be extracted from transaction ordering, inclusion, and block construction.

Front-running is one form of MEV. Others include:

- back-running;
- sandwich attacks;
- liquidation racing;
- arbitrage insertion;
- censorship of competing trades.

This module focuses on a simplified front-running case that is easy to teach and test locally: a user wants to swap ETH for tokens, but the protocol gives them no way to say, “Only execute this swap if I get at least X tokens.”

That missing bound is the vulnerability.

## The Vulnerable Contract: `VulnerableETHToTokenAMM`

The vulnerable AMM uses a constant-product style quote:

```solidity
tokensOut = (ethIn * tokenReserve) / (ethReserveBefore + ethIn);
```

That is not the problem by itself. Dynamic pricing is normal in AMMs.

The real problem is the swap function:

```solidity
function swapExactETHForTokens() external payable returns (uint256 tokensOut) {
    tokensOut = getTokenAmountOut(msg.value);
    require(token.transfer(msg.sender, tokensOut), "Token transfer failed");
}
```

What is missing:

- no `minTokensOut`;
- no `deadline`;
- no user protection against price movement between quote observation and execution.

That means the user effectively says:

- “Execute at any price the pool happens to have by the time my transaction lands.”

In a public mempool, that is a dangerous default.

## Step-by-Step Attack Walkthrough

The tests model a realistic scenario:

- a liquidity provider seeds the pool with 100 ETH and 1000 tokens;
- the victim wants to swap 10 ETH for tokens;
- the attacker watches the victim’s intent;
- the attacker buys 20 ETH worth of tokens first.

Now the exploit happens:

1. The victim reads the current quote for 10 ETH.
2. Before the victim transaction executes, the attacker submits a buy transaction.
3. The attacker’s transaction is included first.
4. The pool’s token reserve decreases and ETH reserve increases.
5. The victim transaction executes against the new, worse price.
6. Because the victim specified no minimum acceptable output, the transaction still succeeds.
7. The victim receives significantly fewer tokens than expected.

The victim did not suffer a logic revert. The victim suffered an economic exploit through ordering.

## Why the Price Gets Worse

In a constant-product style market, buying tokens with ETH:

- adds ETH to the pool;
- removes tokens from the pool.

After the attacker buys first:

- `ethReserve` is higher;
- `tokenReserve` is lower.

That combination makes the victim’s later ETH purchase return fewer tokens.

The AMM is behaving correctly from a math perspective. The failure is that the user had no execution guardrail.

## EVM and Mempool Perspective

At the EVM level, each transaction sees the state as it exists at execution time, not at submission time.

That means:

- the victim may sign based on one price;
- the EVM may execute against a completely different price;
- unless the contract checks a user-specified bound, execution still succeeds.

This is why front-running is fundamentally about transaction ordering and state transitions, not just about Solidity syntax.

The mempool exposes intent. The block builder controls order. The contract must give the user a way to reject bad execution.

## Line-by-Line Analysis of `Vulnerable.sol`

### `getTokenAmountOut(uint256 ethIn)`

This computes the current quote. There is nothing inherently insecure about exposing quotes.

The real risk appears when users rely on quotes but the protocol does not let them enforce those expectations at execution time.

### `swapExactETHForTokens()`

This is the vulnerable flow:

```solidity
tokensOut = getTokenAmountOut(msg.value);
require(token.transfer(msg.sender, tokensOut), "Token transfer failed");
```

What is wrong:

- the user cannot specify the minimum acceptable output;
- the user cannot specify a deadline;
- the protocol silently accepts any worse price caused by ordering changes.

This is exactly the kind of design that MEV actors exploit in production systems.

## Line-by-Line Analysis of `Attack.sol`

### `frontrunBuy()`

This function simply buys tokens before the victim does. It does not need any privileged access. It only needs to move first.

That is what makes front-running so dangerous: the attack often looks like an ordinary market action, but timed to extract value from a known pending user action.

### Why the attacker benefits

Even in this simplified teaching setup, the attacker ends up owning tokens acquired before the victim’s worse execution. In richer real-world scenarios, the attacker might then:

- sell back afterward;
- complete a sandwich;
- arbitrage across venues;
- capture price impact.

This module isolates the front-run phase for clarity.

## The Fixed Contract: `SlippageProtectedETHToTokenAMM`

The fixed version adds exactly the controls users need:

- `minTokensOut`
- `deadline`

The secure swap flow is:

```solidity
require(block.timestamp <= deadline, "Swap expired");
tokensOut = getTokenAmountOut(msg.value);
require(tokensOut >= minTokensOut, "Slippage exceeded");
```

This changes the economics completely.

Now the user says:

- “Execute only if I still get at least this many tokens.”
- “And only before this deadline.”

If the attacker moves the price too far, the victim’s transaction reverts instead of executing at a bad price.

That does not eliminate all MEV from the ecosystem, but it removes the most dangerous part of this specific protocol flaw: forced bad execution.

## Why the Fixed Version Stops the Attack

In the fixed test:

1. The victim reads the quote.
2. The victim sets `minTokensOut` equal to that quote.
3. The attacker buys first and worsens the price.
4. The victim transaction computes a lower `tokensOut`.
5. The contract checks:

```solidity
require(tokensOut >= minTokensOut, "Slippage exceeded");
```

6. The check fails.
7. The victim swap reverts rather than executing at a manipulated price.

That is the correct outcome. A safe protocol should let users reject state changes that violate their own execution assumptions.

## Real-World Context: Why This Matters

This pattern is everywhere in DeFi. If users cannot bound execution quality, they are exposed to:

- front-running;
- sandwich attacks;
- stale execution;
- severe slippage;
- exploitable path changes.

Many real swaps include parameters like:

- `amountOutMin`
- `deadline`
- route validation;
- signed intents;
- off-chain order matching.

These are not optional UX extras. They are security controls against an adversarial execution environment.

## Remediation Strategies

### Always Include Slippage Protection

Users must be able to specify the minimum acceptable output for swaps or the maximum acceptable input for reverse-direction trades.

### Include Deadlines

A deadline prevents old transactions from floating around and executing long after the user’s market assumptions have changed.

### Consider Private Order Flow or Intent-Based Systems

In more advanced architectures, private relays, auctions, or signed intents can reduce mempool exposure. These are not always necessary, but they are relevant for highly MEV-sensitive workflows.

### Make User Intent Explicit

A secure protocol should encode not only “what action” the user wants, but also:

- under what price conditions;
- under what time conditions;
- sometimes under what route conditions.

### Test Adversarial Ordering

Security testing should include state changes inserted before victim execution, not just happy-path swaps.

## Best Practices

- Include `minOut` / `maxIn` style bounds in swap flows.
- Include deadlines for price-sensitive actions.
- Treat transaction ordering as adversarial by default.
- Test front-run scenarios explicitly.
- Avoid designs where users silently accept any execution price.
- Document economic assumptions as part of the security model.
- Use safer routing and order-flow strategies in MEV-sensitive systems.
- Remember that correct code can still be economically unsafe.

## Common Developer Mistakes

### Mistake 1: “The AMM math is correct, so the swap is safe”

Correct math does not protect users from bad ordering. Economic safety requires execution bounds too.

### Mistake 2: “Users can just check the current quote before swapping”

The current quote is only a snapshot. It is not a guarantee about execution-time state.

### Mistake 3: “Front-running is not a smart-contract issue”

It absolutely is when the contract design gives users no tools to reject bad execution caused by ordering.

### Mistake 4: “A revert is worse UX than a bad fill”

In adversarial markets, a revert is often the safe outcome. Silent bad execution can be far more harmful.

### Mistake 5: “MEV only matters for advanced protocols”

Even simple pools, auctions, and price-sensitive actions become MEV-relevant once they are public and order-dependent.

## How to Read the Tests in This Module

The vulnerable test shows:

- the victim observes a quote;
- the attacker trades first;
- the victim still executes, but receives fewer tokens than expected.

The fixed tests show:

- the same pre-trade price movement now causes a revert if output drops below `minTokensOut`;
- a normal honest trade still succeeds when the pool state remains within the user’s declared bounds.

This is exactly what a good fix should do: preserve legitimate functionality while refusing manipulated execution.

## Why This Module Feels Like a Real Audit Case

Many front-running tutorials talk about mempool visibility in the abstract, but stop before connecting it to contract-level design. In real audits, the questions are more practical:

- can the user specify execution bounds?
- does the protocol enforce those bounds?
- what happens if state changes before the transaction lands?
- does the contract protect the user from stale or manipulated execution?

This module is built around those practical questions. It shows a realistic swap vulnerability, a simple attacker flow, and a mitigation that would make sense in a production AMM.

## Conclusion

Front-running and MEV are not just “market phenomena.” They become protocol vulnerabilities when contract interfaces fail to encode the user’s execution assumptions.

The key lessons from this module are:

- transaction ordering is adversarial;
- execution-time state may differ from submission-time state;
- users need slippage and timing protections to avoid forced bad execution.

If you build the habit of asking, “What if the state changes before this transaction is included, and does the user have a way to reject that new state?”, you are thinking like a smart-contract security engineer. That is exactly the mindset this lab is designed to teach.
