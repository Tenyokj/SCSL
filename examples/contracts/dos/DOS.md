<p align="center">
  <img src="../../../public/SCSL_banner.png" alt="SCSL banner" width="100%" style="max-height: 220px; object-fit: cover; object-position: center;" />
</p>

# DOS: Full Educational Module on Denial of Service in Solidity

## Introduction

Denial of Service, usually shortened to DoS, is one of the most underrated categories of smart-contract vulnerabilities. Many developers focus on direct theft: reentrancy, access-control bypass, signature replay, or arithmetic mistakes. Those are obviously dangerous because funds move to the attacker. DoS bugs are different. In a DoS scenario, the attacker may not steal anything directly, but they prevent the protocol from functioning as intended. The result can still be disastrous: auctions become impossible to outbid, withdrawals stop working, governance actions cannot execute, liquidations freeze, or critical administrative functions become permanently unavailable.

In smart contracts, availability is part of security. A protocol that cannot progress is a protocol that can fail economically, reputationally, and operationally. If users cannot submit bids, withdraw funds, claim rewards, or settle positions, the system is effectively broken even if no one has “stolen” the money.

This module focuses on a very realistic DoS anti-pattern: an auction contract that tries to refund the previous highest bidder immediately, inside the same transaction that accepts a new bid. That design looks convenient, but it creates a dangerous dependency on the previous bidder’s fallback behavior. If the previous bidder is a malicious contract that always reverts on incoming Ether, every higher bid fails too. The auction is frozen.

This educational module includes:

- a vulnerable push-refund auction;
- an attacker contract that rejects refunds on purpose;
- a fixed pull-refund auction;
- tests showing the freeze and the mitigation;
- a detailed explanation of why the DoS happens and how to prevent it.

The core lesson is simple but extremely important: **never let one untrusted external recipient decide whether the rest of your protocol can continue.**

## What Denial of Service Means in Solidity

In Solidity, DoS means an attacker can stop a contract, function, workflow, or protocol path from executing successfully. This can happen for many reasons:

- forced reverts in callback paths;
- gas exhaustion in unbounded loops;
- griefing through malicious recipients;
- storage growth that makes actions too expensive;
- state conditions that can never be cleared;
- external integrations that become mandatory and fragile.

Unlike theft-based bugs, DoS often targets liveness rather than ownership. The attacker wants to block progress. That may be enough to manipulate outcomes, lock users out, prevent competition, or force off-chain intervention.

## The Vulnerability Pattern in This Module

The vulnerable contract is an auction that stores:

- the current highest bidder;
- the current highest bid;
- the seller address;
- an end time.

When a new bidder calls `bid()`, the contract tries to refund the previous highest bidder immediately:

```solidity
if (highestBidder != address(0)) {
    (bool success, ) = payable(highestBidder).call{value: highestBid}("");
    require(success, "Refund transfer failed");
}
```

This is the dangerous design choice.

Why? Because the success of a new honest bid now depends on whether the previous highest bidder is willing to accept Ether right now. If that previous bidder is a malicious contract with a reverting `receive()`, the refund fails and the new bid reverts.

That means the attacker can become the leader once, then permanently block everyone else from outbidding them.

## Step-by-Step Attack Walkthrough

The test suite models a realistic scenario:

- Alice places a 1 ETH bid;
- Bob outbids Alice with 2 ETH;
- the attacker contract outbids Bob with 3 ETH;
- the attacker contract is written to reject any refund;
- Charlie tries to place a higher 4 ETH bid.

Here is what happens:

1. Charlie calls `bid()` with 4 ETH.
2. The auction sees that 4 ETH is greater than the current highest bid of 3 ETH.
3. Before accepting Charlie’s bid, the auction tries to refund the attacker contract 3 ETH.
4. The attacker contract’s `receive()` function reverts intentionally.
5. The refund fails.
6. The `require(success, "Refund transfer failed")` line reverts the entire bid.
7. Charlie cannot become the new leader.
8. The attacker remains the highest bidder even though honest users are willing to bid more.

This is a textbook contract-level DoS: a single malicious participant blocks protocol progress by making one required external call fail.

## Why This Works at the EVM Level

At the EVM level, the sequence is straightforward:

1. `Charlie -> PushRefundAuction.bid()`
2. Inside `bid()`, the auction performs `call{value: highestBid}("")` to the current leader.
3. The current leader is the attacker contract.
4. The EVM executes the attacker contract’s `receive()` function.
5. `receive()` runs `require(!rejectRefunds, "Refund rejected intentionally")`.
6. Because `rejectRefunds == true`, the attacker reverts.
7. The low-level `call` returns `success == false`.
8. The auction then executes `require(success, "Refund transfer failed")` and reverts.

The key problem is that the vulnerable contract made its own progress depend on an untrusted external recipient completing successfully.

## Why This Is a Serious Real-World Problem

Developers sometimes dismiss DoS because “no funds were stolen.” That is a dangerous way to think.

In an auction system, DoS can:

- let an attacker lock in an unfair winning position;
- prevent price discovery;
- reduce protocol revenue;
- break fairness guarantees;
- force administrators to pause or redeploy the system.

In a rewards or withdrawals system, the same pattern can:

- block all claims because one recipient reverts;
- freeze batched payouts;
- trap user funds behind a single bad address;
- create cascading operational failures.

Availability is a core security property. If users cannot interact with the system as designed, the protocol is compromised.

## Line-by-Line Analysis of `Vulnerable.sol`

### `address public highestBidder;`

This tracks who is currently winning the auction. By itself, that is normal and expected.

### `uint256 public highestBid;`

This tracks the current winning amount. Again, nothing is wrong here.

### `function bid() external payable onlyBeforeEnd`

This is the critical flow. The function does two important things:

1. checks that the new bid is higher than the current one;
2. tries to refund the previous leader immediately.

The vulnerable section is:

```solidity
if (highestBidder != address(0)) {
    (bool success, ) = payable(highestBidder).call{value: highestBid}("");
    require(success, "Refund transfer failed");
}
```

Why this is unsafe:

- `highestBidder` may be a malicious contract;
- the auction pushes Ether before safely finalizing the state transition;
- the next honest user’s bid depends on an untrusted external call;
- one revert is enough to stop all future bids.

### `settleAuction()`

This function is not the main source of the vulnerability, but it is useful for realism. Auctions usually need a settlement path. The real lesson is that any inline payout can become a DoS surface if the protocol demands immediate recipient cooperation.

## Line-by-Line Analysis of `Attack.sol`

### `bool public rejectRefunds = true;`

This flag controls whether the attacker contract accepts incoming Ether. When it is `true`, refunds revert. This models an attacker who is not trying to receive the refund at all. Their goal is simply to block the auction.

### `placeBlockingBid()`

This function lets the attacker operator become the highest bidder using the malicious contract itself. Once the attack contract is the leader, all future outbids must refund it first.

### `receive()`

This is the core DoS trigger:

```solidity
require(!rejectRefunds, "Refund rejected intentionally");
```

If the auction tries to refund the attacker while `rejectRefunds` is still true, the transfer fails and the new bid reverts.

### `disableRefundBlock()` and `claimRefund()`

These functions exist to make the fixed-case demonstration more realistic. In a safe pull-payment system, the attacker can still reject unsolicited pushes, but later choose to accept a queued refund on their own terms.

That is the correct separation of concerns:

- the protocol should continue progressing;
- the recipient should decide when to claim funds;
- one recipient should not be able to halt everyone else.

## The Fixed Contract: `PullRefundAuction`

The secure version uses a pull-payment pattern. Instead of refunding the old highest bidder immediately inside `bid()`, it stores the amount in `pendingReturns`:

```solidity
pendingReturns[highestBidder] += highestBid;
```

Then the function updates the leader and completes successfully without depending on any external refund transfer.

Later, outbid users can call:

```solidity
withdrawRefund()
```

This design is much safer because:

- new bids no longer depend on the previous bidder’s fallback behavior;
- malicious recipients cannot block auction progress;
- refund logic is isolated into a dedicated withdrawal path;
- the contract follows a more robust liveness model.

## Why the Fixed Version Works

Suppose the attacker contract becomes the highest bidder at 3 ETH and still rejects all incoming Ether. Then Charlie submits a 4 ETH bid.

In the fixed auction:

1. Charlie calls `bid()` with 4 ETH.
2. The contract sees that the old highest bidder was the attacker.
3. Instead of sending 3 ETH back immediately, the contract records:
   `pendingReturns[attacker] += 3 ether`
4. The contract updates `highestBidder = Charlie`.
5. The bid succeeds.

Notice what changed:

- the attacker’s fallback never executes during Charlie’s bid;
- the attack contract gets no opportunity to block the state transition;
- the auction remains live.

Later, the attacker may disable its refund rejection and explicitly call `withdrawRefund()` through the helper contract. That is fine. The critical security point is that the attacker no longer controls whether the auction can accept higher bids.

## Real-World Analogy: Auction and Payment Griefing

The general pattern demonstrated here has appeared in different forms across Ethereum history. One commonly cited family of examples involves contracts that attempt to “pay everyone now” or “refund the old leader now.” If any participant has a reverting fallback or unexpectedly expensive logic, the whole action can fail.

The broader lesson also appears in systems beyond auctions:

- dividend payout loops;
- mass reward distributions;
- batch withdrawals;
- NFT mint refund logic;
- liquidation or settlement loops;
- governance reward claims.

Whenever progress depends on completing an external payment to an arbitrary recipient right now, you should pause and ask whether that recipient can refuse the payment and freeze the system.

## Remediation Strategies

### Use Pull Payments Instead of Push Payments

This is the main fix in this module. Record what a user is owed and let them withdraw it later in a separate call.

### Isolate External Interactions

Do not couple a protocol’s critical progression path with external recipient execution. A new bid, position update, governance step, or settlement decision should not depend on an arbitrary recipient’s fallback succeeding.

### Follow Checks-Effects-Interactions

Even in DoS-oriented cases, CEI helps:

1. validate input;
2. update internal state;
3. interact externally only when necessary.

### Avoid Unbounded Loops Over User-Controlled Recipient Sets

Many DoS bugs come from trying to iterate over all users or all payout recipients in one transaction. If one iteration fails or the loop becomes too expensive, the whole flow breaks.

### Design for Liveness, Not Only Correctness

A contract can be logically correct in a happy path and still be insecure if one malicious participant can stop everyone else from using it.

## Best Practices

- Prefer pull-payment refund patterns over inline refund pushes.
- Treat every external recipient as potentially malicious or unavailable.
- Separate critical protocol progression from optional payout collection.
- Add tests that include attacker contracts with reverting `receive()` functions.
- Review auctions, batched payouts, and settlement flows for liveness risks.
- Keep refund bookkeeping explicit and easy to audit.
- Avoid making one user’s success a prerequisite for another user’s action.
- Verify that honest users can continue operating even when a malicious participant refuses to cooperate.

## Common Developer Mistakes

### Mistake 1: “Refunding immediately is more user friendly, so it must be better”

Sometimes immediate refunds feel simpler for UX, but they may create liveness dependencies that are much worse than the convenience they provide.

### Mistake 2: “A recipient would never reject Ether”

Contracts can reject Ether intentionally, accidentally, or because their logic changed. You must design for hostile recipients, not ideal recipients.

### Mistake 3: “This is only a minor annoyance, not a real vulnerability”

In an auction, a frozen highest bidder is a severe integrity problem. In a payment system, a frozen withdrawal path is a severe availability problem. DoS is often economically critical.

### Mistake 4: “Low-level `call` solves the issue because it is flexible”

Using `call` instead of `transfer` does not fix the fundamental problem. The real issue is not the opcode choice; it is the dependency on immediate external cooperation.

### Mistake 5: “If the state is correct, liveness doesn’t matter”

State correctness and liveness are both security properties. A system that is permanently stuck is not secure.

## How to Read the Tests in This Module

The vulnerable test shows:

- honest bids succeed at first;
- the attacker contract becomes the leader;
- a higher honest bid fails because the attacker rejects refunds;
- the attacker remains the winner even though the auction should still be competitive.

The fixed tests show:

- the same attacker can no longer freeze the bidding process;
- honest users can outbid the attacker;
- queued refunds can still be withdrawn later in a controlled way.

This is exactly what we want from a mitigation: preserve protocol progress without trapping legitimate funds.

## Why This Module Feels Like a Real Audit Case

Many DoS tutorials are too shallow. They say “loops are bad” or “external calls can revert,” but they do not connect that to real product behavior. In practice, auditors care about questions like:

- can one user block other users from interacting?
- can a malicious recipient freeze the business flow?
- does the protocol progress depend on untrusted cooperation?
- is there a pull-based alternative that preserves liveness?

This module is built around those questions. It shows a realistic auction pattern, a practical attacker contract, and a mitigation that would make sense in production.

## Conclusion

Denial of Service in Solidity is not just about crashing a function. It is about breaking liveness and making a protocol stop serving honest users. In many systems, that is just as damaging as direct theft.

The key lesson from this module is:

- do not push critical refunds inline to untrusted recipients;
- do not let one participant’s fallback behavior decide whether everyone else can proceed;
- prefer pull-payment designs that preserve protocol progress.

If you build the habit of asking, “Can this untrusted recipient make the whole workflow revert?”, you are thinking like a smart-contract security engineer. That is exactly the mindset this lab is designed to teach.
