// Shield Protocol Types

export interface ShieldConfig {
  dailySpendLimit: bigint
  singleTxLimit: bigint
  spentToday: bigint
  lastResetTimestamp: bigint
  isActive: boolean
  emergencyMode: boolean
}

export interface DCAStrategy {
  user: `0x${string}`
  sourceToken: `0x${string}`
  targetToken: `0x${string}`
  amountPerExecution: bigint
  minAmountOut: bigint
  intervalSeconds: bigint
  nextExecutionTime: bigint
  totalExecutions: bigint
  executionsCompleted: bigint
  poolFee: number
  status: StrategyStatus
  createdAt: bigint
  updatedAt: bigint
}

export enum StrategyStatus {
  Active = 0,
  Paused = 1,
  Completed = 2,
  Cancelled = 3,
}

export enum StopLossType {
  FixedPrice = 0,
  Percentage = 1,
  TrailingStop = 2,
}

export enum StopLossStatus {
  Active = 0,
  Triggered = 1,
  Paused = 2,
  Cancelled = 3,
}

// Rebalance Strategy types
export interface AssetAllocation {
  token: `0x${string}`
  targetWeight: bigint
  currentWeight: bigint
}

export interface RebalanceStrategy {
  user: `0x${string}`
  allocations: AssetAllocation[]
  rebalanceThreshold: bigint
  minRebalanceInterval: bigint
  lastRebalanceTime: bigint
  totalRebalances: bigint
  poolFee: number
  status: StrategyStatus
  createdAt: bigint
  updatedAt: bigint
}

export interface CreateRebalanceParams {
  tokens: `0x${string}`[]
  targetWeights: bigint[]
  rebalanceThreshold: bigint
  minRebalanceInterval: bigint
  poolFee: number
}

// Stop-Loss Strategy types
export interface StopLossStrategy {
  user: `0x${string}`
  tokenToSell: `0x${string}`
  tokenToReceive: `0x${string}`
  amount: bigint
  stopLossType: StopLossType
  triggerPrice: bigint
  triggerPercentage: bigint
  trailingDistance: bigint
  highestPrice: bigint
  minAmountOut: bigint
  poolFee: number
  status: StopLossStatus
  createdAt: bigint
  triggeredAt: bigint
  executedAmount: bigint
}

export interface CreateStopLossParams {
  tokenToSell: `0x${string}`
  tokenToReceive: `0x${string}`
  amount: bigint
  stopLossType: StopLossType
  triggerValue: bigint
  trailingDistance: bigint
  minAmountOut: bigint
  poolFee: number
}

export interface StrategyStats {
  totalIn: bigint
  totalOut: bigint
  averagePrice: bigint
  executionsCompleted: bigint
}

export interface TokenInfo {
  address: `0x${string}`
  symbol: string
  decimals: number
  name?: string
}

export interface CreateStrategyParams {
  sourceToken: `0x${string}`
  targetToken: `0x${string}`
  amountPerExecution: bigint
  minAmountOut: bigint
  intervalSeconds: bigint
  totalExecutions: bigint
  poolFee: number
}

// Token list for Sepolia
export const SUPPORTED_TOKENS: TokenInfo[] = [
  {
    address: '0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14',
    symbol: 'WETH',
    decimals: 18,
    name: 'Wrapped Ether',
  },
  {
    address: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
    symbol: 'USDC',
    decimals: 6,
    name: 'USD Coin',
  },
]

export function getTokenByAddress(address: string): TokenInfo | undefined {
  return SUPPORTED_TOKENS.find(
    (t) => t.address.toLowerCase() === address.toLowerCase()
  )
}

export function getStatusLabel(status: StrategyStatus): string {
  const labels: Record<StrategyStatus, string> = {
    [StrategyStatus.Active]: 'Active',
    [StrategyStatus.Paused]: 'Paused',
    [StrategyStatus.Completed]: 'Completed',
    [StrategyStatus.Cancelled]: 'Cancelled',
  }
  return labels[status]
}

export function getStatusColor(status: StrategyStatus): string {
  const colors: Record<StrategyStatus, string> = {
    [StrategyStatus.Active]: 'success',
    [StrategyStatus.Paused]: 'warning',
    [StrategyStatus.Completed]: 'secondary',
    [StrategyStatus.Cancelled]: 'destructive',
  }
  return colors[status]
}
