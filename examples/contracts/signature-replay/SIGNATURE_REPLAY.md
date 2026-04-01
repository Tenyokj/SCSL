<p align="center">
  <img src="../../../public/SCSL_banner.png" alt="SCSL banner" width="100%" style="max-height: 220px; object-fit: cover; object-position: center;" />
</p>

# SIGNATURE REPLAY: Full Educational Module on Replayable Off-Chain Authorizations in Solidity

## Introduction

Signature-based authorization is one of the most common patterns in modern Solidity systems. Instead of forcing an authorized account to execute every action on-chain, a trusted signer can authorize an operation off-chain and let someone else submit the signature later. This model is powerful because it enables:

- gasless claims;
- permit-style approvals;
- delegated execution;
- off-chain approvals for withdrawals or rewards;
- meta-transactions;
- batched and asynchronous workflows.

But signature systems are only secure if every signed authorization is scoped correctly. A valid signature should usually be bound to:

- a specific beneficiary;
- a specific action;
- a specific amount;
- a specific contract;
- a specific chain;
- a specific nonce;
- often a deadline as well.

If any of these protections are missing, the same signature may become reusable in unintended contexts. That is the essence of signature replay.

This module demonstrates a realistic replay vulnerability in an Ether vault. The vault lets users claim funds with an off-chain signature from an authorized signer. But the signed message contains no nonce, no expiry, and no replay tracking. As a result, the same signature can be submitted again and again by the same beneficiary until the vault is drained.

This module includes:

- a vulnerable replayable-signature vault;
- an attacker contract that reuses the same signed claim repeatedly;
- a fixed vault that adds nonce, deadline, and domain separation;
- tests proving both the exploit and the mitigation;
- a detailed explanation of why replay happens and how to prevent it.

The key lesson is simple: **a valid signature is not automatically a one-time authorization. If you do not encode one-time semantics, the chain will not invent them for you.**

## What Signature Replay Means

Signature replay happens when a signed message that was intended to authorize a single action can instead be submitted multiple times, or in more contexts than intended.

A replayable signature is dangerous because cryptographic validity alone does not imply limited use. A signature merely proves that some signer approved some message. It does not prove:

- that the message has never been used before;
- that it is only valid on one chain;
- that it applies to only one contract;
- that it expires at some point;
- that it is unique to a particular transaction flow.

If the contract does not encode those constraints and enforce them, the same signature may keep working.

## The Vulnerable Contract: `ReplayableSignatureVault`

The vulnerable vault trusts an `authorizedSigner` to approve withdrawals off-chain.

The claim function verifies a digest built from:

```solidity
keccak256(abi.encodePacked(msg.sender, amount, address(this)))
```

That is not enough.

What is missing:

- no nonce;
- no deadline;
- no storage tracking of consumed signatures;
- no per-beneficiary execution count.

As long as the signature remains valid for the same `msg.sender`, `amount`, and contract address, the beneficiary can reuse it repeatedly.

## Step-by-Step Attack Walkthrough

The tests model a realistic scenario:

- an authorized signer exists;
- honest users deposit 7 ETH into the vault;
- the signer authorizes a single 1 ETH claim for the attacker contract;
- the attacker contract receives that valid signature once.

Now the exploit works like this:

1. The attacker contract calls `claim(1 ether, signature)`.
2. The vault verifies that the signature is valid for:
   - `msg.sender == attackerContract`
   - `amount == 1 ether`
   - `address(this) == vulnerableVault`
3. The vault transfers 1 ETH to the attacker contract.
4. The attacker contract calls the exact same `claim()` again with the exact same signature.
5. The vault has no nonce tracking and no used-message record, so the same signature is still accepted.
6. The process repeats until the attacker has taken 5 ETH from the vault.

This is a true replay bug. The signer intended one authorization. The contract interpreted it as unlimited repeated authorizations.

## Why the Replay Works at the EVM and Contract Levels

At the cryptographic level, the signature is perfectly valid every time because the message hash is identical every time:

```text
hash(msg.sender, amount, vaultAddress)
```

Nothing changes between calls:

- same claimant;
- same amount;
- same contract.

Because the digest stays the same, `ecrecover` keeps returning the same authorized signer.

At the contract level, the fatal mistake is that the contract never marks the authorization as consumed. The chain has no memory that “this message was already used” unless the contract writes that fact into storage.

That is the core replay lesson:

- cryptographic validity is stateless;
- one-time usage is a stateful property;
- stateful properties must be enforced on-chain.

## Line-by-Line Analysis of `Vulnerable.sol`

### `address public immutable authorizedSigner;`

This is the account allowed to approve withdrawals. That part is fine by itself. Many secure systems use a designated signer.

### `claim(uint256 amount, bytes calldata signature)`

This is the critical path.

The function:

- checks that `amount > 0`;
- checks the vault has enough Ether;
- reconstructs the signed digest;
- recovers the signer with `ecrecover`;
- transfers Ether if the signer matches.

All of that sounds reasonable, but it misses the most important replay defenses:

- there is no nonce;
- there is no expiry;
- there is no used-signature tracking.

### `keccak256(abi.encodePacked(msg.sender, amount, address(this)))`

Including `msg.sender` and `address(this)` is better than signing only the amount. It prevents some cross-user and cross-contract misuse. But it still does not make the authorization one-time. The same beneficiary can reuse the same message forever.

## Line-by-Line Analysis of `Attack.sol`

### `attack(uint256 amountPerClaim, bytes calldata signature, uint256 replayCount)`

This function loops and reuses the same signature multiple times. That models the real exploit precisely.

The important point is that the attacker is not forging cryptography. They are exploiting missing protocol semantics. The signer signed once. The contract keeps honoring that approval indefinitely.

### `if (target.vaultBalance() < amountPerClaim) { break; }`

This makes the exploit adaptive. It stops if the remaining balance becomes too small. In real attacks, exploit loops often read the current state and extract as much as possible without reverting unnecessarily.

### `withdrawLoot()`

After the replay loop, the stolen Ether sits inside the attacker contract and is forwarded to the operator.

## The Fixed Contract: `NoncedSignatureVault`

The secure version introduces the standard replay defenses:

- `nonces[msg.sender]`
- `deadline`
- `block.chainid`
- `address(this)`

The signed digest becomes:

```solidity
keccak256(
    abi.encodePacked(
        block.chainid,
        address(this),
        msg.sender,
        amount,
        currentNonce,
        deadline
    )
)
```

This improves security in several ways:

- `currentNonce` makes each authorization one-time;
- `deadline` limits how long the signature remains valid;
- `block.chainid` prevents cross-chain replay;
- `address(this)` prevents cross-contract replay.

Then, before transferring Ether, the contract increments the nonce:

```solidity
nonces[msg.sender] = currentNonce + 1;
```

That ensures the same signature becomes invalid immediately after first use.

## Why the Fixed Version Stops Replay

Suppose the signer authorizes:

- beneficiary = claimant
- amount = 1 ETH
- nonce = 0
- deadline = T

The first call succeeds because the digest matches exactly.

After the first call:

- `nonces[claimant]` becomes `1`

Now if the same signature is reused, the contract computes a new digest using nonce `1`, but the signature was created over nonce `0`. The recovered signer no longer matches, so the call reverts with `Invalid signature`.

That is the correct behavior. The signed message was truly one-time because its validity depended on mutable contract state.

## Real-World Context: Why Replay Bugs Matter

Replay vulnerabilities show up in many real systems:

- permit implementations;
- reward claim systems;
- signed withdrawals;
- bridge authorizations;
- OTC order settlement;
- meta-transaction relayers;
- administrative off-chain approvals.

The exact surface differs, but the core failure is usually the same: a signature that was intended for one use, one chain, one contract, or one time period ends up being accepted in a broader context.

Historically, replay bugs have been especially dangerous because developers often think, “the signer approved it, so it must be safe.” But approval is not enough. The contract must define **how many times**, **where**, and **until when** that approval is valid.

## Remediation Strategies

### Use Nonces

Nonces are the most important replay defense. Each authorization should consume a unique nonce so it cannot be reused.

### Include Deadlines

Even if a signature is intended to be used once, adding an expiry reduces long-lived risk from leaked or forgotten authorizations.

### Include Domain Separation

A good signed message should usually include:

- `block.chainid`
- `address(this)`

Without these, the same signature may be replayed across chains or across contracts with compatible logic.

### Mark Authorizations as Consumed Before External Effects

State that prevents replay should be updated before transferring funds or making external calls.

### Prefer Established Signing Standards When Appropriate

Patterns such as EIP-712 make message structure clearer and safer, especially for complex systems. Even when using simpler signed-message flows, the same replay-prevention principles still apply.

## Best Practices

- Always include a nonce in signed authorization flows.
- Include a deadline for time-bounded validity.
- Include chain ID and contract address to prevent replay across environments.
- Update replay-protection state before transferring assets.
- Test repeated submission of the same signature explicitly.
- Treat off-chain authorization logic as part of the core security boundary.
- Keep signed message formats well documented and consistent.
- Audit beneficiary binding carefully so signatures cannot be stolen and replayed by another caller.

## Common Developer Mistakes

### Mistake 1: “If the signature is valid, the claim should succeed”

A valid signature only proves signer approval of a message. It does not prove that the message is still fresh or unused.

### Mistake 2: “Including `msg.sender` is enough replay protection”

Binding a signature to the beneficiary prevents some misuse, but not replay by that same beneficiary.

### Mistake 3: “I included the contract address, so replay is solved”

Including the contract address prevents cross-contract replay, not repeated use inside the same contract.

### Mistake 4: “Users will only submit the signature once”

Security must not depend on expected user behavior. If a signature remains valid, someone will eventually reuse it, whether intentionally or accidentally.

### Mistake 5: “Replay only matters for tokens”

No. Replay bugs are relevant anywhere signatures authorize value movement, permissions, orders, or privileged actions.

## How to Read the Tests in This Module

The vulnerable tests show:

- honest users funding the vault;
- a signer authorizing one 1 ETH claim;
- the attacker contract replaying that same signature five times;
- the vault losing 5 ETH even though only one claim was intended.

The fixed tests show:

- a proper nonce-bound authorization working once;
- the nonce incrementing after the first claim;
- reuse of the same signature failing afterward;
- normal legitimate signed claims still working.

This is exactly what we want from a secure signature system: preserve usability while removing replay semantics.

## Why This Module Feels Like a Real Audit Case

Many replay tutorials are too abstract. They explain “add a nonce” without showing what actually goes wrong economically. In real audits, the important questions are:

- what exactly is the signed message?
- what contexts can replay it?
- who can benefit from replay?
- where is freshness enforced?
- how is one-time use encoded?

This module is built around those practical questions. The vulnerable code is not just cryptographically incomplete. It is economically exploitable.

## Conclusion

Signature replay is one of the clearest examples of the difference between cryptographic validity and protocol correctness. A signature can be perfectly valid and still completely unsafe if the contract does not restrict when and how often it may be used.

The key lessons from this module are:

- signatures do not become one-time by default;
- replay protection must be encoded explicitly on-chain;
- nonce, deadline, and domain separation are essential building blocks.

If you train yourself to ask, “What makes this signature fresh, unique, and non-reusable?”, you are thinking like a smart-contract security engineer. That is exactly the mindset this lab is designed to develop.
