// Contract addresses on Sepolia
export const CONTRACT_ADDRESSES = {
  shieldCore: '0xB581368a7eb6130FFa27BbE29574bF5E231d0c7A' as `0x${string}`,
  dcaExecutor: '0x4056Da36F0f980537F8C211fA08FE6530E8D1FaB' as `0x${string}`,
  rebalanceExecutor: '0x27a6339DEAC4cd08cE2Ec9a7ff6Bdeeabe1962C2' as `0x${string}`,
  stopLossExecutor: '0x77034c6f5962ECf30C3DC72d33f7409fdCE7c89f' as `0x${string}`,
  subscriptionManager: '0x6E03B2088E767E5f954fFaa05a7fD6bae14CfE8b' as `0x${string}`,
  usdc: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238' as `0x${string}`,
  weth: '0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14' as `0x${string}`,
}

// DCAExecutor ABI (only needed functions)
export const DCA_EXECUTOR_ABI = [
  {
    inputs: [{ name: 'user', type: 'address' }],
    name: 'getUserStrategies',
    outputs: [{ name: '', type: 'bytes32[]' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'strategyId', type: 'bytes32' }],
    name: 'getStrategy',
    outputs: [
      {
        components: [
          { name: 'user', type: 'address' },
          { name: 'sourceToken', type: 'address' },
          { name: 'targetToken', type: 'address' },
          { name: 'amountPerExecution', type: 'uint256' },
          { name: 'minAmountOut', type: 'uint256' },
          { name: 'intervalSeconds', type: 'uint256' },
          { name: 'nextExecutionTime', type: 'uint256' },
          { name: 'totalExecutions', type: 'uint256' },
          { name: 'executionsCompleted', type: 'uint256' },
          { name: 'poolFee', type: 'uint24' },
          { name: 'status', type: 'uint8' },
          { name: 'createdAt', type: 'uint256' },
          { name: 'updatedAt', type: 'uint256' },
        ],
        name: '',
        type: 'tuple',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'strategyId', type: 'bytes32' }],
    name: 'canExecute',
    outputs: [
      { name: '', type: 'bool' },
      { name: '', type: 'string' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'strategyId', type: 'bytes32' }],
    name: 'executeDCA',
    outputs: [{ name: 'amountOut', type: 'uint256' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { name: 'startIndex', type: 'uint256' },
      { name: 'limit', type: 'uint256' },
    ],
    name: 'getPendingStrategies',
    outputs: [
      { name: 'strategyIds', type: 'bytes32[]' },
      { name: 'nextIndex', type: 'uint256' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  // Events
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'strategyId', type: 'bytes32' },
      { indexed: true, name: 'user', type: 'address' },
      { indexed: false, name: 'amountIn', type: 'uint256' },
      { indexed: false, name: 'amountOut', type: 'uint256' },
      { indexed: false, name: 'executionsCompleted', type: 'uint256' },
      { indexed: false, name: 'timestamp', type: 'uint256' },
    ],
    name: 'DCAExecuted',
    type: 'event',
  },
] as const

// SubscriptionManager ABI (only needed functions)
export const SUBSCRIPTION_MANAGER_ABI = [
  {
    inputs: [{ name: 'subscriber', type: 'address' }],
    name: 'getSubscriberSubscriptions',
    outputs: [{ name: '', type: 'bytes32[]' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'subscriptionId', type: 'bytes32' }],
    name: 'getSubscription',
    outputs: [
      {
        components: [
          { name: 'subscriptionId', type: 'bytes32' },
          { name: 'subscriber', type: 'address' },
          { name: 'recipient', type: 'address' },
          { name: 'token', type: 'address' },
          { name: 'amount', type: 'uint256' },
          { name: 'billingPeriod', type: 'uint8' },
          { name: 'nextPaymentTime', type: 'uint256' },
          { name: 'paymentsCompleted', type: 'uint256' },
          { name: 'maxPayments', type: 'uint256' },
          { name: 'status', type: 'uint8' },
          { name: 'createdAt', type: 'uint256' },
          { name: 'cancelledAt', type: 'uint256' },
        ],
        name: '',
        type: 'tuple',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'subscriptionId', type: 'bytes32' }],
    name: 'canExecutePayment',
    outputs: [
      { name: 'canPay', type: 'bool' },
      { name: 'reason', type: 'string' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'subscriptionId', type: 'bytes32' }],
    name: 'executePayment',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  // Events
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: 'subscriptionId', type: 'bytes32' },
      { indexed: true, name: 'subscriber', type: 'address' },
      { indexed: true, name: 'recipient', type: 'address' },
      { indexed: false, name: 'amount', type: 'uint256' },
      { indexed: false, name: 'paymentNumber', type: 'uint256' },
      { indexed: false, name: 'timestamp', type: 'uint256' },
    ],
    name: 'PaymentExecuted',
    type: 'event',
  },
] as const

// Strategy status enum
export enum StrategyStatus {
  Active = 0,
  Paused = 1,
  Completed = 2,
  Cancelled = 3,
}

// Subscription status enum
export enum SubscriptionStatus {
  Active = 0,
  Paused = 1,
  Cancelled = 2,
  Expired = 3,
}

// RebalanceExecutor ABI (only needed functions)
export const REBALANCE_EXECUTOR_ABI = [
  {
    inputs: [{ name: 'user', type: 'address' }],
    name: 'getUserStrategies',
    outputs: [{ name: '', type: 'bytes32[]' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'strategyId', type: 'bytes32' }],
    name: 'getStrategy',
    outputs: [
      {
        components: [
          { name: 'user', type: 'address' },
          {
            name: 'allocations',
            type: 'tuple[]',
            components: [
              { name: 'token', type: 'address' },
              { name: 'targetWeight', type: 'uint256' },
              { name: 'currentWeight', type: 'uint256' },
            ],
          },
          { name: 'rebalanceThreshold', type: 'uint256' },
          { name: 'minRebalanceInterval', type: 'uint256' },
          { name: 'lastRebalanceTime', type: 'uint256' },
          { name: 'totalRebalances', type: 'uint256' },
          { name: 'poolFee', type: 'uint24' },
          { name: 'status', type: 'uint8' },
          { name: 'createdAt', type: 'uint256' },
          { name: 'updatedAt', type: 'uint256' },
        ],
        name: '',
        type: 'tuple',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'strategyId', type: 'bytes32' }],
    name: 'needsRebalance',
    outputs: [
      { name: 'needed', type: 'bool' },
      { name: 'reason', type: 'string' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'strategyId', type: 'bytes32' }],
    name: 'executeRebalance',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [{ name: 'strategyId', type: 'bytes32' }],
    name: 'getPortfolioValue',
    outputs: [{ name: 'totalValue', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const

// StopLossExecutor ABI (only needed functions)
export const STOP_LOSS_EXECUTOR_ABI = [
  {
    inputs: [{ name: 'user', type: 'address' }],
    name: 'getUserStrategies',
    outputs: [{ name: '', type: 'bytes32[]' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'strategyId', type: 'bytes32' }],
    name: 'getStrategy',
    outputs: [
      {
        components: [
          { name: 'user', type: 'address' },
          { name: 'tokenToSell', type: 'address' },
          { name: 'tokenToReceive', type: 'address' },
          { name: 'amount', type: 'uint256' },
          { name: 'stopLossType', type: 'uint8' },
          { name: 'triggerPrice', type: 'uint256' },
          { name: 'triggerPercentage', type: 'uint256' },
          { name: 'trailingDistance', type: 'uint256' },
          { name: 'highestPrice', type: 'uint256' },
          { name: 'minAmountOut', type: 'uint256' },
          { name: 'poolFee', type: 'uint24' },
          { name: 'status', type: 'uint8' },
          { name: 'createdAt', type: 'uint256' },
          { name: 'triggeredAt', type: 'uint256' },
          { name: 'executedAmount', type: 'uint256' },
        ],
        name: '',
        type: 'tuple',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'strategyId', type: 'bytes32' }],
    name: 'shouldTrigger',
    outputs: [
      { name: 'triggered', type: 'bool' },
      { name: 'currentPrice', type: 'uint256' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [{ name: 'strategyId', type: 'bytes32' }],
    name: 'checkAndExecute',
    outputs: [{ name: 'executed', type: 'bool' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [{ name: 'strategyId', type: 'bytes32' }],
    name: 'getCurrentTriggerPrice',
    outputs: [{ name: '', type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const

// Rebalance status enum
export enum RebalanceStatus {
  Active = 0,
  Paused = 1,
  Cancelled = 2,
}

// StopLoss type enum
export enum StopLossType {
  FixedPrice = 0,
  Percentage = 1,
  TrailingStop = 2,
}

// StopLoss status enum
export enum StopLossStatus {
  Active = 0,
  Triggered = 1,
  Executed = 2,
  Paused = 3,
  Cancelled = 4,
}
