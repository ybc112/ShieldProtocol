<div align="center">

# Shield Protocol

### Intent-Driven Smart Asset Protection & Automation Platform

**Built on MetaMask Advanced Permissions (ERC-7715) + EIP-7702**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-363636.svg)](https://soliditylang.org/)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.0-3178C6.svg)](https://www.typescriptlang.org/)
[![Next.js](https://img.shields.io/badge/Next.js-14-black.svg)](https://nextjs.org/)

[Demo Video](#demo) • [Documentation](#documentation) • [Quick Start](#quick-start) • [Architecture](#architecture)

</div>

---

## The Problem

Web3 users face critical challenges that hinder mainstream adoption:

| Problem | Impact | Current Solutions |
|---------|--------|-------------------|
| **Unlimited Token Approvals** | $120M+ lost in 2024 (Badger DAO, Radiant Capital exploits) | Manual revocation via revoke.cash - reactive, not proactive |
| **Manual DCA Execution** | Users miss optimal entry points, emotional trading | Gelato/Chainlink Keepers - requires trusting third-party infrastructure |
| **No Native Subscriptions** | Web3 services resort to token-gating or upfront payments | Superfluid - separate protocol, not wallet-native |
| **Complex Multi-step UX** | Each swap requires 2+ transactions (approve + execute) | Account Abstraction - fragmented implementations |

> *"Only 10.8% of users regularly check unused token approvals"* - Georgia Tech DeFi Security Research 2025

### Why This Matters

```
📊 DeFi Security Statistics (2024):
├── $120M+ lost to approval exploits
├── 89.2% of users never check token approvals
├── Average user has 15+ active unlimited approvals
└── 73% of hacks exploit existing approvals
```

---

## The Solution: Shield Protocol

Shield Protocol is the **first intent-driven asset protection platform** built natively on MetaMask's ERC-7715 Advanced Permissions. Instead of granting unlimited access, users express **what they want to achieve** while Shield handles execution within **cryptographically enforced boundaries**.

```
Traditional Flow:                    Shield Protocol Flow:

User → Approve(∞) → DApp → Risk!    User → "Buy $20 ETH daily for 30 days"
                                           ↓
                                    MetaMask → Grant Permission(limited)
                                           ↓
                                    Shield → Execute within bounds ✓
```

### Core Innovation: Intent-Centric Permissions

Unlike transaction-based protocols, Shield uses an **intent-centric architecture**:

```typescript
// User expresses intent, not transaction details
const userIntent = {
  goal: "Accumulate ETH using DCA strategy",
  constraints: {
    maxSpendPerDay: "20 USDC",
    duration: "30 days",
    slippageTolerance: "1%"
  }
};

// Shield translates to ERC-7715 permission
const permission = {
  type: "erc20-spend-recurring-limit",
  data: {
    token: USDC_ADDRESS,
    limit: parseUnits("20", 6),
    period: 86400, // 24 hours
    startTime: Math.floor(Date.now() / 1000),
    validityPeriod: 30 * 86400
  }
};
```

---

## Key Features

### 1. Smart Shield - Proactive Asset Protection

Real-time protection that stops threats **before** they drain your wallet.

| Feature | Description | Technical Implementation |
|---------|-------------|-------------------------|
| **Spending Limits** | Daily/weekly maximum transfer caps | `erc20-spend-recurring-limit` permission |
| **Whitelist-Only Mode** | Only interact with verified contracts | Caveat-based delegation restrictions |
| **Anomaly Detection** | ML-powered unusual activity alerts | Envio real-time event indexing |
| **Emergency Freeze** | One-click permission revocation | `DelegationManager.disableDelegation()` |

```solidity
// Example: Caveat that limits spending to $100/day
struct SpendingLimitCaveat {
    address token;
    uint256 dailyLimit;
    uint256 spentToday;
    uint256 lastResetTimestamp;
}
```

### 2. Auto-Pilot Investment Strategies

Set your investment goals, Shield executes automatically.

| Strategy | Description | Permission Type |
|----------|-------------|-----------------|
| **DCA (Dollar Cost Average)** | Regular purchases regardless of price | `erc20-spend-recurring-limit` |
| **Smart Rebalance** | Maintain target portfolio ratios | Multi-token spending permissions |
| **Stop-Loss Guardian** | Auto-sell when price drops X% | Price-conditional execution |
| **Yield Reinvest** | Compound staking rewards automatically | Protocol-specific permissions |

```typescript
// DCA Strategy Configuration
const dcaStrategy = await shield.createStrategy({
  type: "DCA",
  params: {
    sourceToken: "USDC",
    targetToken: "ETH",
    amountPerExecution: parseUnits("20", 6),
    frequency: "daily",
    duration: 30, // days
    dexRouter: "0x..." // Uniswap V3
  }
});
```

### 3. Web3 Native Subscriptions

Finally, recurring payments that work like Web2 - but with full user control.

```typescript
// Subscribe to a content creator
const subscription = await shield.subscribe({
  recipient: creatorAddress,
  amount: parseUnits("10", 6), // 10 USDC
  token: USDC_ADDRESS,
  interval: "monthly",
  // User can cancel anytime - unused funds stay in their wallet
});
```

### 4. AI Agent Integration (🚧 Coming Soon - Phase 3)

> **⚠️ Status**: This feature is **planned for Phase 3** (2025 Q3-Q4). The code below shows the intended API design.

Grant limited permissions to AI agents for autonomous DeFi operations with cryptographically enforced boundaries.

**Why AI Agents Need Shield:**
```
Traditional AI Agent Problem:          Shield Solution:
─────────────────────────────────────────────────────────────
❌ Full wallet access                 → ✅ Fine-grained permissions
❌ Unlimited spending                 → ✅ Per-tx & daily limits
❌ No protocol restrictions           → ✅ Allowlisted protocols only
❌ Permanent access                   → ✅ Time-bound permissions
❌ Opaque operations                  → ✅ Full transparency & logging
```

**Planned Features:**
- 🤖 Natural language strategy creation ("Buy ETH when RSI < 30")
- 🔒 Fine-grained permission control with spending limits
- 📊 Real-time market analysis and automated decision making
- ⚡ Cross-protocol yield optimization
- 🛡️ Anomaly detection and auto-pause
- 📜 Complete audit trail for all agent actions

**Planned Security Boundaries:**
| Constraint | Description |
|------------|-------------|
| `maxValuePerTx` | Maximum value per single transaction |
| `maxDailyVolume` | Maximum total volume per 24 hours |
| `allowedProtocols` | Whitelist of DeFi protocols |
| `allowedTokens` | Whitelist of tokens to operate |
| `expiry` | Permission auto-expires after set time |
| `capabilities` | Allowed action types (swap/stake/lend) |

```typescript
// 🚧 PLANNED API - Not yet implemented
// Example of how AI Agent permissions will work in Phase 3

// 1. User grants limited permission to AI agent
const agentPermission = await shield.grantAgentPermission({
  agent: aiAgentAddress,
  capabilities: ["swap", "stake", "provide-liquidity"],
  constraints: {
    maxValuePerTx: parseEther("0.5"),      // Max 0.5 ETH per tx
    maxDailyVolume: parseEther("5"),       // Max 5 ETH per day
    allowedProtocols: ["uniswap-v3", "aave-v3"],
    allowedTokens: ["ETH", "USDC", "WBTC"]
  },
  expiry: Date.now() + 30 * 24 * 60 * 60 * 1000 // 30 days
});

// 2. AI Agent operates within boundaries (agent-side code)
const result = await agentSDK.executeWithPermission({
  permissionId: permission.id,
  action: {
    type: "swap",
    fromToken: "USDC",
    toToken: "ETH",
    amount: parseUnits("100", 6)
  }
});

// 3. User can monitor agent activity anytime
const activity = await shield.getAgentActivity(aiAgentAddress);

// 4. User can instantly revoke permission
await shield.revokeAgentPermission(permission.id);
```

**Planned Timeline:**
- Q3 2025: AgentPermissionManager contract + basic SDK
- Q4 2025: Natural language parsing + market analysis AI
- 2026: Agent marketplace + reputation system

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Frontend (Next.js + Wagmi)                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐  │
│  │ Shield       │  │ Strategy     │  │ Analytics Dashboard      │  │
│  │ Dashboard    │  │ Builder      │  │ (Envio-powered)          │  │
│  └──────────────┘  └──────────────┘  └──────────────────────────┘  │
└─────────────────────────────────┬───────────────────────────────────┘
                                  │
┌─────────────────────────────────▼───────────────────────────────────┐
│              MetaMask Smart Accounts Kit + ERC-7715                 │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  wallet_grantPermissions() ──► DeleGator Smart Account     │    │
│  │                                     │                       │    │
│  │  Permission Types:                  │  Delegation Types:    │    │
│  │  • erc20-spend-recurring-limit      │  • HybridDelegator    │    │
│  │  • erc20-stream-transfer            │  • MultisigDelegator  │    │
│  │  • native-token-stream              │                       │    │
│  └────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────┬───────────────────────────────────┘
                                  │
┌─────────────────────────────────▼───────────────────────────────────┐
│                    Smart Contract Layer (Solidity)                  │
│                                                                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │
│  │ ShieldCore.sol  │  │ StrategyVault   │  │ Subscription    │     │
│  │                 │  │ .sol            │  │ Manager.sol     │     │
│  │ • Permission    │  │                 │  │                 │     │
│  │   validation    │  │ • DCA executor  │  │ • Recurring     │     │
│  │ • Limit checks  │  │ • Rebalancer    │  │   payments      │     │
│  │ • Emergency     │  │ • Stop-loss     │  │ • Stream        │     │
│  │   controls      │  │   triggers      │  │   management    │     │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘     │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    DelegationManager.sol                     │   │
│  │  • Caveat enforcement  • Multi-hop delegations              │   │
│  │  • Delegation storage  • Redemption validation              │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────┬───────────────────────────────────┘
                                  │
┌─────────────────────────────────▼───────────────────────────────────┐
│                      Envio HyperIndex Layer                         │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Real-time Event Indexing (2000x faster than RPC)           │   │
│  │                                                              │   │
│  │  Events Tracked:                GraphQL API:                 │   │
│  │  • PermissionGranted            query GetUserShield {        │   │
│  │  • PermissionRevoked              permissions { ... }        │   │
│  │  • StrategyExecuted               strategies { ... }         │   │
│  │  • AnomalyDetected                alerts { ... }             │   │
│  │  • SpendingLimitHit             }                            │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### Prerequisites

- Node.js v18+
- [MetaMask Flask](https://metamask.io/flask/) v12.14.2+
- [Pimlico API Key](https://dashboard.pimlico.io/) (for bundler/paymaster)

### Installation

```bash
# Clone the repository
git clone https://github.com/your-username/shield-protocol.git
cd shield-protocol

# Install dependencies
yarn install

# Configure environment
cp .env.example .env
# Edit .env with your API keys:
# - NEXT_PUBLIC_PIMLICO_API_KEY
# - NEXT_PUBLIC_RPC_URL (Sepolia)
# - ENVIO_API_KEY

# Start development server
yarn dev
```

### Project Structure

```
shield-protocol/
├── apps/
│   └── web/                    # Next.js frontend
│       ├── src/
│       │   ├── app/            # App router pages
│       │   ├── components/     # React components
│       │   ├── hooks/          # Custom hooks (useShield, useStrategy)
│       │   ├── providers/      # Context providers
│       │   └── services/       # API & blockchain services
│       └── package.json
│
├── packages/
│   ├── contracts/              # Solidity smart contracts
│   │   ├── src/
│   │   │   ├── ShieldCore.sol
│   │   │   ├── StrategyVault.sol
│   │   │   ├── SubscriptionManager.sol
│   │   │   └── caveats/
│   │   │       ├── SpendingLimitCaveat.sol
│   │   │       └── WhitelistCaveat.sol
│   │   └── test/
│   │
│   ├── sdk/                    # Shield Protocol SDK
│   │   └── src/
│   │       ├── Shield.ts
│   │       ├── Strategy.ts
│   │       └── types.ts
│   │
│   └── indexer/                # Envio indexer
│       ├── config.yaml
│       ├── schema.graphql
│       └── src/
│           └── EventHandlers.ts
│
└── package.json
```

---

## Smart Contract Reference

### ShieldCore.sol

Core contract managing permissions and security rules.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DelegationManager} from "@metamask/delegation-framework/DelegationManager.sol";
import {ICaveatEnforcer} from "@metamask/delegation-framework/interfaces/ICaveatEnforcer.sol";

contract ShieldCore {
    DelegationManager public delegationManager;

    struct ShieldConfig {
        uint256 dailySpendLimit;
        uint256 singleTxLimit;
        address[] whitelistedContracts;
        bool emergencyMode;
    }

    mapping(address => ShieldConfig) public userShields;

    event ShieldActivated(address indexed user, ShieldConfig config);
    event SpendingLimitUpdated(address indexed user, uint256 newLimit);
    event EmergencyModeTriggered(address indexed user);

    function activateShield(ShieldConfig calldata config) external {
        userShields[msg.sender] = config;
        emit ShieldActivated(msg.sender, config);
    }

    function triggerEmergency() external {
        userShields[msg.sender].emergencyMode = true;
        // Revoke all active delegations
        emit EmergencyModeTriggered(msg.sender);
    }
}
```

### StrategyVault.sol

Executes automated investment strategies within permission boundaries.

```solidity
contract StrategyVault {
    struct DCAStrategy {
        address user;
        address sourceToken;
        address targetToken;
        uint256 amountPerExecution;
        uint256 intervalSeconds;
        uint256 nextExecutionTime;
        uint256 executionsRemaining;
        address dexRouter;
    }

    mapping(bytes32 => DCAStrategy) public strategies;

    function executeDCA(bytes32 strategyId) external {
        DCAStrategy storage strategy = strategies[strategyId];
        require(block.timestamp >= strategy.nextExecutionTime, "Too early");
        require(strategy.executionsRemaining > 0, "Strategy completed");

        // Execute swap via delegation
        // Permission limits are enforced by DelegationManager
        _executeSwap(strategy);

        strategy.nextExecutionTime += strategy.intervalSeconds;
        strategy.executionsRemaining--;

        emit DCAExecuted(strategyId, strategy.amountPerExecution);
    }
}
```

---

## ERC-7715 Permission Examples

### Requesting DCA Permission

```typescript
import { createWalletClient, custom } from "viem";
import { erc7715ProviderActions } from "@metamask/delegation-toolkit/experimental";

const walletClient = createWalletClient({
  transport: custom(window.ethereum),
}).extend(erc7715ProviderActions());

// Request permission for DCA strategy
const permission = await walletClient.grantPermissions([{
  chainId: sepolia.id,
  expiry: Math.floor(Date.now() / 1000) + 30 * 86400, // 30 days
  signer: {
    type: "account",
    data: { address: shieldVaultAddress },
  },
  permission: {
    type: "erc20-spend-recurring-limit",
    data: {
      token: USDC_ADDRESS,
      limit: parseUnits("20", 6).toString(), // 20 USDC per period
      period: 86400, // 24 hours
    },
  },
}]);
```

### Redeeming Permission (Executing DCA)

```typescript
import { DelegationFramework } from "@metamask/delegation-toolkit";

const framework = new DelegationFramework({
  delegationManager: DELEGATION_MANAGER_ADDRESS,
  bundlerUrl: `https://api.pimlico.io/v2/sepolia/rpc?apikey=${PIMLICO_KEY}`,
});

// Execute DCA using granted permission
const userOp = await framework.redeemDelegation({
  delegation: grantedPermission.delegation,
  action: {
    target: UNISWAP_ROUTER,
    value: 0n,
    calldata: encodeSwapCalldata(USDC, ETH, parseUnits("20", 6)),
  },
});

await framework.sendUserOperation(userOp);
```

---

## Envio Integration

### Schema Definition

```graphql
# schema.graphql
type User @entity {
  id: ID!
  address: Bytes!
  shields: [Shield!]! @derivedFrom(field: "user")
  strategies: [Strategy!]! @derivedFrom(field: "user")
  totalProtectedValue: BigInt!
}

type Shield @entity {
  id: ID!
  user: User!
  dailyLimit: BigInt!
  singleTxLimit: BigInt!
  whitelistedContracts: [Bytes!]!
  isEmergencyMode: Boolean!
  createdAt: BigInt!
}

type Strategy @entity {
  id: ID!
  user: User!
  type: StrategyType!
  sourceToken: Bytes!
  targetToken: Bytes!
  amountPerExecution: BigInt!
  executionsCompleted: Int!
  totalVolume: BigInt!
  status: StrategyStatus!
}

type Execution @entity {
  id: ID!
  strategy: Strategy!
  timestamp: BigInt!
  amountIn: BigInt!
  amountOut: BigInt!
  txHash: Bytes!
}

enum StrategyType {
  DCA
  REBALANCE
  STOP_LOSS
  YIELD_REINVEST
}

enum StrategyStatus {
  ACTIVE
  PAUSED
  COMPLETED
  CANCELLED
}
```

### Event Handlers

```typescript
// src/EventHandlers.ts
import { ShieldCore, StrategyVault } from "generated";

ShieldCore.ShieldActivated.handler(async ({ event, context }) => {
  const userId = event.params.user.toLowerCase();

  await context.User.upsert({
    id: userId,
    create: {
      address: event.params.user,
      totalProtectedValue: 0n,
    },
    update: {},
  });

  await context.Shield.create({
    id: `${userId}-${event.block.number}`,
    data: {
      user_id: userId,
      dailyLimit: event.params.config.dailySpendLimit,
      singleTxLimit: event.params.config.singleTxLimit,
      whitelistedContracts: event.params.config.whitelistedContracts,
      isEmergencyMode: false,
      createdAt: event.block.timestamp,
    },
  });
});

StrategyVault.DCAExecuted.handler(async ({ event, context }) => {
  const strategyId = event.params.strategyId;

  await context.Execution.create({
    id: `${event.transaction.hash}-${event.log.logIndex}`,
    data: {
      strategy_id: strategyId,
      timestamp: event.block.timestamp,
      amountIn: event.params.amountIn,
      amountOut: event.params.amountOut,
      txHash: event.transaction.hash,
    },
  });
});
```

---

## Demo Flow

### Scenario: Setting Up Protected DCA Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│  Step 1: Connect & Activate Shield                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  [Connect MetaMask Flask]                                │   │
│  │                                                          │   │
│  │  Shield Configuration:                                   │   │
│  │  • Daily Spending Limit: [100] USDC                     │   │
│  │  • Single Transaction Limit: [50] USDC                  │   │
│  │  • Emergency Contact: [0x...]                           │   │
│  │                                                          │   │
│  │  [Activate Shield] ← Creates Smart Account               │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  Step 2: Create DCA Strategy                                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Strategy Builder:                                       │   │
│  │                                                          │   │
│  │  I want to: [Buy ▼]                                      │   │
│  │  Token: [ETH ▼]                                          │   │
│  │  Using: [20] [USDC ▼]                                    │   │
│  │  Frequency: [Daily ▼]                                    │   │
│  │  Duration: [30] days                                     │   │
│  │                                                          │   │
│  │  Total: 600 USDC over 30 days                           │   │
│  │                                                          │   │
│  │  [Create Strategy]                                       │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  Step 3: Grant Permission (MetaMask Popup)                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  🦊 MetaMask                                             │   │
│  │                                                          │   │
│  │  Shield Protocol requests permission:                    │   │
│  │                                                          │   │
│  │  ✓ Spend up to 20 USDC per day                          │   │
│  │  ✓ Valid for 30 days                                    │   │
│  │  ✓ Only for DCA execution                               │   │
│  │                                                          │   │
│  │  ⚠️ Maximum total: 600 USDC                              │   │
│  │                                                          │   │
│  │  [Reject]                    [Approve]                   │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  Step 4: Monitor on Dashboard (Envio-powered)                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  📊 DCA Strategy: ETH Accumulation                       │   │
│  │                                                          │   │
│  │  Progress: ████████░░░░░░░░ 12/30 days                   │   │
│  │                                                          │   │
│  │  Total Invested: 240 USDC                               │   │
│  │  ETH Acquired: 0.0892 ETH                               │   │
│  │  Avg. Price: $2,690.58                                  │   │
│  │                                                          │   │
│  │  Recent Executions:                                      │   │
│  │  • Nov 26: 20 USDC → 0.0074 ETH @ $2,702               │   │
│  │  • Nov 25: 20 USDC → 0.0076 ETH @ $2,631               │   │
│  │  • Nov 24: 20 USDC → 0.0073 ETH @ $2,739               │   │
│  │                                                          │   │
│  │  [Pause] [Cancel] [Modify]                              │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🚀 Innovation & Key Differentiators

### Why Shield Protocol is Different

| Innovation | Description | Benefit |
|------------|-------------|---------|
| **🔐 Intent-Driven Architecture** | Users express goals ("Buy $20 ETH daily"), not transactions | Simplified UX, reduced errors |
| **🛡️ ERC-7715 Native Permissions** | First platform built on MetaMask's new permission standard | Wallet-native security, no trust assumptions |
| **⚡ EIP-7702 Smart Accounts** | EOA upgrades to smart account while keeping same address | Seamless migration, batch transactions |
| **📊 Multi-layer Protection** | Daily limits + Single tx limits + Whitelist + Emergency freeze | Defense in depth |
| **🔄 Unified Automation** | DCA + Rebalance + Stop-Loss + Subscriptions in one platform | Single permission, multiple strategies |
| **⏰ Time-locked Security** | 24h cooldown for config changes, 48h for emergency withdrawals | Protection against key compromise |
| **📈 Price Anomaly Detection** | Auto-pause strategies on 20%+ price deviation | Flash crash protection |

### Problems We Solve

```
Traditional DeFi Problems          →  Shield Solutions
─────────────────────────────────────────────────────────────
❌ Unlimited approvals             →  ✅ Fine-grained, time-limited permissions
❌ Manual DCA (150 clicks/month)   →  ✅ One-time setup, auto-execution
❌ No spending limits              →  ✅ Daily & per-transaction caps
❌ Complex multi-step UX           →  ✅ Intent-driven, single approval
❌ Reactive security (revoke.cash) →  ✅ Proactive protection (limits + whitelist)
❌ Trust third-party keepers       →  ✅ Cryptographic guarantees via ERC-7715
❌ No native Web3 subscriptions    →  ✅ Built-in recurring payments
❌ Fragmented tools                →  ✅ All-in-one protection platform
```

---

## Competitive Advantage

| Feature | Shield Protocol | Gelato | Superfluid | Traditional DApps |
|---------|-----------------|--------|------------|-------------------|
| **Permission Model** | ERC-7715 Native | External Keeper | Protocol-specific | Unlimited Approvals |
| **Wallet Integration** | MetaMask Native | Any wallet | Any wallet | Any wallet |
| **Spending Limits** | Built-in | Manual setup | N/A | N/A |
| **Emergency Stop** | One-click | Complex | Complex | Manual revoke |
| **Trust Requirement** | Cryptographic | Keeper network | Protocol | Full trust |
| **Gas Efficiency** | Smart Account batching | Per-execution | Streaming | Per-transaction |
| **Data Analytics** | Real-time indexing | Basic | Basic | None |

---

## Roadmap

### Phase 1: MVP ✅ (Current)
- [x] Core permission management (ShieldCore)
- [x] DCA strategy execution (DCAExecutor)
- [x] Rebalance & Stop-Loss strategies
- [x] Web3 native subscriptions (SubscriptionManager)
- [x] Spending limit enforcers (Caveat system)
- [x] Time-locked security (24h config, 48h emergency)
- [x] Price anomaly detection
- [x] Real-time data indexing
- [x] MetaMask Flask support

### Phase 2: Enhanced Protection (Next)
- [ ] ML-powered anomaly detection
- [ ] Social recovery integration
- [ ] Multi-chain support (post EIP-7702 mainnet)
- [ ] Advanced analytics dashboard
- [ ] Mobile app support

### Phase 3: AI Agent Framework (Future)
- [ ] Natural language strategy creation ("Buy ETH when RSI < 30")
- [ ] AI-powered autonomous portfolio management
- [ ] Cross-protocol yield optimization
- [ ] Risk assessment AI advisor
- [ ] Predictive market analysis

### Phase 4: Ecosystem
- [ ] SDK for third-party integrations
- [ ] Strategy marketplace
- [ ] DAO governance

---

## Tech Stack

| Category | Technology |
|----------|------------|
| **Frontend** | Next.js 14, React 18, TypeScript, TailwindCSS |
| **Web3** | Wagmi v2, Viem, MetaMask Smart Accounts Kit |
| **Smart Contracts** | Solidity 0.8.24, Hardhat, OpenZeppelin |
| **Permissions** | ERC-7715, EIP-7702, Delegation Toolkit |
| **Indexing** | Envio HyperIndex, GraphQL |
| **Infrastructure** | Pimlico (Bundler/Paymaster), Sepolia Testnet |

---

## Resources

### Official Documentation
- [MetaMask Smart Accounts Kit](https://docs.metamask.io/smart-accounts-kit/)
- [ERC-7715 Specification](https://eips.ethereum.org/EIPS/eip-7715)
- [EIP-7702 Overview](https://eip7702.io/)
- [Delegation Toolkit](https://docs.metamask.io/delegation-toolkit/)
- [Envio Documentation](https://docs.envio.dev/)

### Example Repositories
- [MetaMask ERC-7715 Template](https://github.com/MetaMask/templated-gator-7715)
- [Delegation Framework](https://github.com/MetaMask/delegation-framework)

---

## Advanced Permissions Usage

Shield Protocol is built natively on MetaMask's ERC-7715 Advanced Permissions standard. Here's how we implement permission request and redemption:

### Requesting Advanced Permissions

Users grant fine-grained, time-limited permissions through our Shield activation and strategy creation flows:

- **Shield Activation (Spending Limits)**: [`web/src/hooks/useShield.ts`](web/src/hooks/useShield.ts) - `useActivateShield()` hook requests permission to enforce daily and per-transaction spending limits
- **DCA Strategy Creation**: [`web/src/hooks/useStrategy.ts`](web/src/hooks/useStrategy.ts) - `useCreateStrategy()` hook requests recurring spending permissions for automated DCA execution
- **Rebalance Strategy**: [`web/src/hooks/useRebalance.ts`](web/src/hooks/useRebalance.ts) - Requests multi-token spending permissions for portfolio rebalancing
- **Stop-Loss Strategy**: [`web/src/hooks/useStopLoss.ts`](web/src/hooks/useStopLoss.ts) - Requests conditional execution permissions for stop-loss triggers
- **Subscription Creation**: [`web/src/hooks/useSubscription.ts`](web/src/hooks/useSubscription.ts) - Requests recurring payment permissions

### Redeeming Advanced Permissions

Backend executor services redeem granted permissions to execute automated strategies:

- **DCA Executor**: [`backend/src/services/dcaExecutor.ts`](backend/src/services/dcaExecutor.ts) - Redeems permissions to execute scheduled DCA swaps within user-defined limits
- **Rebalance Executor**: [`backend/src/services/rebalanceExecutor.ts`](backend/src/services/rebalanceExecutor.ts) - Redeems permissions to rebalance portfolios when thresholds are met
- **Stop-Loss Executor**: [`backend/src/services/stopLossExecutor.ts`](backend/src/services/stopLossExecutor.ts) - Redeems permissions to execute stop-loss orders when price conditions trigger
- **Subscription Executor**: [`backend/src/services/subscriptionExecutor.ts`](backend/src/services/subscriptionExecutor.ts) - Redeems permissions to process recurring subscription payments

### Smart Contract Permission Enforcement

- **ShieldCore Contract**: [`contracts/src/core/ShieldCore.sol`](contracts/src/core/ShieldCore.sol) - Enforces spending limits and whitelist restrictions
- **DCAExecutor Contract**: [`contracts/src/executors/DCAExecutor.sol`](contracts/src/executors/DCAExecutor.sol) - Validates and executes DCA strategies within permission bounds

---

## Envio Usage

Shield Protocol uses **Ponder** (Envio-compatible indexer) for real-time blockchain event indexing, powering our analytics dashboard and strategy monitoring.

### How We Use Envio/Ponder

1. **Real-time Event Indexing**: Index all Shield Protocol contract events for instant dashboard updates
2. **Strategy Tracking**: Track DCA executions, rebalance operations, and stop-loss triggers
3. **User Analytics**: Aggregate user spending, investment totals, and strategy performance
4. **Global Statistics**: Calculate protocol-wide metrics (total users, volume, executions)

### Code Links

- **Indexer Configuration**: [`indexer/ponder.config.ts`](indexer/ponder.config.ts) - Defines indexed contracts and chain configuration
- **Database Schema**: [`indexer/ponder.schema.ts`](indexer/ponder.schema.ts) - Defines all indexed entities (users, shields, strategies, executions, etc.)
- **ShieldCore Event Handlers**: [`indexer/src/ShieldCore.ts`](indexer/src/ShieldCore.ts) - Handles shield activation, config updates, emergency mode, spending records
- **DCA Event Handlers**: [`indexer/src/DCAExecutor.ts`](indexer/src/DCAExecutor.ts) - Handles strategy creation, execution, pause/resume/cancel events
- **Rebalance Event Handlers**: [`indexer/src/RebalanceExecutor.ts`](indexer/src/RebalanceExecutor.ts) - Handles rebalance strategy events
- **Stop-Loss Event Handlers**: [`indexer/src/StopLossExecutor.ts`](indexer/src/StopLossExecutor.ts) - Handles stop-loss strategy events
- **Subscription Event Handlers**: [`indexer/src/SubscriptionManager.ts`](indexer/src/SubscriptionManager.ts) - Handles subscription and payment events
- **GraphQL API**: [`indexer/src/api/index.ts`](indexer/src/api/index.ts) - Custom API endpoints for frontend queries

### Indexed Data

| Entity | Description |
|--------|-------------|
| `user` | User profiles with aggregated stats |
| `shield` | Shield configurations and spending limits |
| `dcaStrategy` | DCA strategy details and execution stats |
| `dcaExecution` | Individual DCA execution records |
| `rebalanceStrategy` | Rebalance strategy configurations |
| `stopLossStrategy` | Stop-loss strategy configurations |
| `subscription` | Subscription details and payment history |
| `activityLog` | User activity timeline |
| `globalStats` | Protocol-wide statistics |

---

## Team

Building at MetaMask Advanced Permissions Hackathon 2024

---

## License

MIT License - see [LICENSE](LICENSE) for details

---

<div align="center">

**Shield Protocol** - *Your assets, your rules, automated.*

[Website](#) • [Twitter](#) • [Discord](#)

</div>
