# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Werk is a decentralized platform for freelancers and small companies. It uses ERC-4337 Account Abstraction with a modular smart account system to manage payments and compensation streaming on-chain. License: GPL-3.0-or-later.

## Build & Development Commands

```bash
bun install                    # Install dependencies
forge build                    # Build contracts (or: bun run build)
forge test -vvv                # Run all tests with verbosity
forge test --mt testFunctionName -vvv  # Run a single test by name
forge test --mc ContractName   # Run all tests in a specific contract
forge fmt                      # Format Solidity files
bun run lint                   # Run all linters (solhint + prettier)
bun run lint:sol               # Solhint + forge fmt --check
bun run prettier:check         # Check formatting for non-sol files
```

**CI profile** (used in GitHub Actions): `FOUNDRY_PROFILE=optimized forge build`

**Coverage:** `bash script/coverage.sh`

**Deployment:** See `Makefile` targets (e.g., `make deploy-deterministic-station-registry`). All deployments use CREATE3 for deterministic addresses across chains.

## Architecture

### Core Contracts

- **Space** (`src/Space.sol`) — ERC-4337 smart account (vault). Holds ETH, ERC-20, ERC-721, ERC-1155. Executes code only through allowlisted modules. UUPS upgradeable.
- **StationRegistry** (`src/StationRegistry.sol`) — Factory that creates Space proxy instances via ERC1967Proxy. Predicts addresses, manages Space implementation upgrades.
- **ModuleKeeper** (`src/ModuleKeeper.sol`) — Maintains an allowlist of modules that Spaces can execute. Only the owner (Werk team) can manage the list.

### Module System

Modules are pluggable extensions executed by Spaces. Must be allowlisted in ModuleKeeper.

- **PaymentModule** (`src/modules/payment-module/`) — On-chain payment requests payable in ERC-20 or ETH. Supports direct transfer, linear streams, and tranched streams via Sablier Lockup. Has recurring payment support (weekly/monthly/yearly).
- **CompensationModule** (`src/modules/compensation-module/`) — Employer-to-employee compensation streaming via Sablier Flow. Multi-component plans (salary, ESOP, bonuses), each with its own flow stream.

### Peripherals

- **InvoiceCollection** (`src/peripherals/invoice-collection/`) — ERC-721 NFT collection for invoices.
- **ENS Subdomains** (`src/peripherals/ens-domains/`) — werk.eth subdomain registration for Spaces.

### Key Design Patterns

- **ERC-7201 namespaced storage** on all upgradeable contracts to prevent storage collisions.
- **UUPS proxy pattern** with `_disableInitializers()` in constructors.
- **Module allowlisting** — Spaces check ModuleKeeper before executing any module call.
- **AccountCore** (`src/utils/AccountCore.sol`) — Fork of thirdweb's AccountCore adapted for UUPS (renamed `initialize` to `__AccountCore_init`).
- **Custom errors** defined in `src/libraries/Errors.sol`; types in `src/libraries/Types.sol`.

## Test Structure

Tests use Foundry's `forge test`. Base test setup is in `test/Base.t.sol`.

- `test/unit/concrete/` — Isolated unit tests per contract/function (Space, StationRegistry, ModuleKeeper)
- `test/integration/concrete/` — Full module interaction tests (PaymentModule, CompensationModule, InvoiceCollection, ENS)
- `test/integration/fuzz/` — Fuzz tests (10,000 runs configured)
- `test/mocks/` — Mock contracts (MockERC20NoReturn, MockModule, MockBadReceiver, etc.)
- `test/utils/Helpers.sol` — Payment calculation helpers for tests

Integration tests deploy Sablier Lockup/Flow protocols alongside Werk modules.

## Solidity Conventions

- Compiler version: `0.8.30`
- Max line length: 140 (solhint) / 120 (prettier)
- Formatting: `forge fmt` for Solidity, prettier for JSON/MD/YML
- Supported networks: Ethereum Mainnet, Sepolia, Base, Base Sepolia, HyperEVM

## Key Dependencies

- OpenZeppelin Contracts v5 (standards, proxies, upgradeability)
- Thirdweb Contracts (ERC-4337 account abstraction base)
- Sablier Lockup v3 & Flow v2 (token streaming)
- PRBMath (fixed-point math, UD21x18)
- ENS Contracts (subdomain registration)
- Solady (optimized utilities)
