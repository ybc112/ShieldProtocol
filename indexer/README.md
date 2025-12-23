# Shield Protocol Ponder Indexer

Real-time blockchain event indexer for Shield Protocol using [Ponder](https://ponder.sh/).

## Features

- Real-time event indexing from Sepolia testnet
- GraphQL API for querying indexed data
- Automatic database sync with blockchain state
- Support for all Shield Protocol events:
  - Shield activation/deactivation
  - DCA strategy creation and execution
  - Subscription management and payments
  - Activity logging and statistics

## Prerequisites

- Node.js >= 18.14
- npm or yarn
- Sepolia RPC URL (Alchemy, Infura, or QuickNode)

## Quick Start

### 1. Install Dependencies

```bash
cd indexer
npm install
```

### 2. Configure Environment

```bash
cp .env.example .env
```

Edit `.env` and add your Sepolia RPC URL:

```env
PONDER_RPC_URL_11155111=https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY
```

### 3. Start Development Server

```bash
npm run dev
```

The indexer will:
1. Start syncing from block 7200000
2. Create a local SQLite database
3. Expose GraphQL API at `http://localhost:42069`

## Available Scripts

| Command | Description |
|---------|-------------|
| `npm run dev` | Start development server with hot reload |
| `npm run start` | Start production server |
| `npm run codegen` | Generate TypeScript types from schema |
| `npm run serve` | Serve GraphQL API only (no indexing) |

## Contract Addresses (Sepolia)

| Contract | Address |
|----------|---------|
| ShieldCore | `0xB581368a7eb6130FFa27BbE29574bF5E231d0c7A` |
| DCAExecutor | `0x4056Da36F0f980537F8C211fA08FE6530E8D1FaB` |
| SubscriptionManager | `0x6E03B2088E767E5f954fFaa05a7fD6bae14CfE8b` |

## GraphQL API

Once running, access the GraphQL playground at: `http://localhost:42069`

### Example Queries

**Get user with shield config:**
```graphql
query GetUser($address: String!) {
  user(id: $address) {
    id
    address
    totalInvested
    totalDCAExecutions
    shield {
      dailySpendLimit
      singleTxLimit
      spentToday
      isActive
      emergencyMode
    }
  }
}
```

**Get user's DCA strategies:**
```graphql
query GetUserStrategies($userId: String!) {
  dcaStrategys(where: { userId: $userId }) {
    items {
      id
      sourceTokenId
      targetTokenId
      amountPerExecution
      totalExecutions
      executionsCompleted
      status
      totalAmountIn
      totalAmountOut
      averagePrice
    }
  }
}
```

**Get recent activity:**
```graphql
query GetRecentActivity($userId: String!) {
  activityLogs(
    where: { userId: $userId }
    orderBy: "timestamp"
    orderDirection: "desc"
    limit: 20
  ) {
    items {
      id
      eventType
      description
      timestamp
      txHash
    }
  }
}
```

**Get global statistics:**
```graphql
query GetGlobalStats {
  globalStats(id: "global") {
    totalUsers
    totalShieldsActivated
    totalDCAStrategies
    totalDCAExecutions
    totalDCAVolume
    totalSubscriptions
    totalPayments
    totalPaymentVolume
  }
}
```

**Get DCA executions:**
```graphql
query GetDCAExecutions($strategyId: String!) {
  dcaExecutions(
    where: { strategyId: $strategyId }
    orderBy: "timestamp"
    orderDirection: "desc"
  ) {
    items {
      id
      amountIn
      amountOut
      price
      executionNumber
      txHash
      timestamp
    }
  }
}
```

## Database Schema

### Main Tables

| Table | Description |
|-------|-------------|
| `user` | User accounts and aggregate stats |
| `shield` | Shield protection configurations |
| `dcaStrategy` | DCA strategy configurations |
| `dcaExecution` | Individual DCA execution records |
| `subscription` | Subscription configurations |
| `payment` | Individual payment records |
| `activityLog` | All user activity events |
| `dailyStats` | Per-user daily statistics |
| `globalStats` | Protocol-wide statistics |
| `token` | Token metadata |
| `whitelistedContract` | Whitelisted contracts per shield |
| `spendingRecord` | Spending records per shield |

### Entity Relationships

```
User
├── Shield (1:1)
│   ├── WhitelistedContract (1:N)
│   └── SpendingRecord (1:N)
├── DCAStrategy (1:N)
│   └── DCAExecution (1:N)
├── Subscription (as subscriber, 1:N)
│   └── Payment (1:N)
├── Subscription (as recipient, 1:N)
├── ActivityLog (1:N)
└── DailyStats (1:N)

Token
├── DCAStrategy.sourceToken (1:N)
├── DCAStrategy.targetToken (1:N)
├── Subscription.token (1:N)
└── SpendingRecord.token (1:N)

GlobalStats (singleton)
```

## Production Deployment

For production, use PostgreSQL:

```env
DATABASE_URL=postgres://user:password@localhost:5432/shield_indexer
```

Deploy options:
- **Railway**: One-click deploy with PostgreSQL
- **Docker**: Use the official Ponder Docker image
- **Self-hosted**: Any Node.js hosting with PostgreSQL

## Troubleshooting

### RPC Rate Limits

If you hit rate limits, use a paid RPC provider or reduce sync speed:

```ts
// ponder.config.ts
transport: http(process.env.PONDER_RPC_URL_11155111, {
  retryCount: 3,
  retryDelay: 1000,
})
```

### Database Reset

To reset and re-sync:

```bash
rm -rf .ponder
npm run dev
```

## Integration with Frontend

Update your frontend `.env`:

```env
NEXT_PUBLIC_INDEXER_URL=http://localhost:42069
```

Use the GraphQL client in `web/src/lib/graphql.ts` to query data.

### Frontend Integration Example

```typescript
// lib/graphql.ts
import { GraphQLClient } from 'graphql-request'

export const graphqlClient = new GraphQLClient(
  process.env.NEXT_PUBLIC_INDEXER_URL || 'http://localhost:42069'
)

// hooks/useUserData.ts
import { useQuery } from '@tanstack/react-query'
import { graphqlClient } from '@/lib/graphql'
import { GET_USER_QUERY } from '@/lib/queries'

export function useUserData(address: string) {
  return useQuery({
    queryKey: ['user', address],
    queryFn: () => graphqlClient.request(GET_USER_QUERY, {
      address: address.toLowerCase()
    }),
    enabled: !!address,
  })
}
```
