# Library

This directory is reserved for the reusable SCSL Solidity library.

## Structure

```text
library/
  INDEX.sol
  accounting/
  access/
  guards/
  oracle/
  payments/
  proxy/
  signatures/
  storage/
  mocks/
  test/
  time/
  trading/
```

Current first-wave primitives include:

- `guards/ReentrancyGuard.sol`
- `access/TwoStepOwnable.sol`
- `payments/PullPaymentEscrow.sol`
- `signatures/SignatureAuthorizer.sol`
- `proxy/TrustedPluginRegistry.sol`

Second-wave primitives now include:

- `auth/NoncedAuthorizations.sol`
- `trading/ExecutionConstraints.sol`
- `storage/EIP1967SlotAccess.sol`
- `oracle/TrustedPriceOracleConsumer.sol`

Third-wave primitives now include:

- `accounting/BalanceAccounting.sol`
- `payments/NativeTransfer.sol`
- `time/BlockCooldown.sol`

These contracts are meant to be reusable building blocks extracted from the exploit-driven lessons in the `examples/` section.

The library now also has its own test surface under `library/test/`.
Hardhat compiles the test harness layer from `examples/contracts/library/`, which imports the canonical contracts from `library/`.

## Temporary Dev-Only Files

The following directories exist only to support active development and verification:

- `library/mocks/`
- `library/test/`

They are intentionally temporary. Once the reusable primitives are stabilized and the package layer is finalized, these development-only helpers can be removed so the published library surface remains clean and minimal.

## Import Patterns

Import a single primitive directly:

```solidity
import {ReentrancyGuard} from "../library/guards/ReentrancyGuard.sol";
import {TwoStepOwnable} from "../library/access/TwoStepOwnable.sol";
```

Or import from the aggregate entrypoint:

```solidity
import "../library/INDEX.sol";
```

Note: Solidity does not support JavaScript-style symbol re-exports. The `INDEX.sol` files in SCSL are package navigation entrypoints for tooling and human discovery, while actual contract usage should still import the concrete file path of the primitive you need.

## Design Goal

The purpose of `library/` is not to mirror OpenZeppelin line for line. The goal is to provide a smaller, security-focused set of primitives that map directly to the attack classes demonstrated in `examples/`.

That means the library is intentionally opinionated:

- minimal surface area
- explicit custom errors
- clear inheritance boundaries
- patterns derived from the educational exploit modules
- easy auditability over maximal abstraction

## Current Coverage Mapping

- `ReentrancyGuard.sol` maps to the `reentrancy` module
- `TwoStepOwnable.sol` maps to the `access-control` module
- `PullPaymentEscrow.sol` maps to the `dos` module
- `SignatureAuthorizer.sol` maps to the `signature-replay` module
- `TrustedPluginRegistry.sol` maps to the `delegatecall` module
- `NoncedAuthorizations.sol` maps to the `signature-replay` module
- `ExecutionConstraints.sol` maps to the `front-running-mev` and `timestamp-manipulation` modules
- `EIP1967SlotAccess.sol` maps to the `storage-collisions` module
- `TrustedPriceOracleConsumer.sol` maps to the `flash-loans` module
- `BalanceAccounting.sol` maps to the `integer-overflow-underflow` module
- `NativeTransfer.sol` supports safer ETH payout flows used across vault and payment modules
- `BlockCooldown.sol` maps to the `timestamp-manipulation` module

Planned next layers include:

- secure accounting helpers
- nonce and authorization primitives
- safer proxy upgrade utilities
- queue-based payout abstractions
- hardened plugin and module execution patterns

Unlike `examples/`, this layer is intended for direct import into external Solidity projects.
