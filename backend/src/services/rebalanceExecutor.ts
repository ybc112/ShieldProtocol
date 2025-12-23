import {
  createPublicClient,
  createWalletClient,
  http,
  formatUnits,
  type PublicClient,
  type WalletClient,
} from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import { sepolia } from 'viem/chains'
import { config } from '../config/index.js'
import {
  CONTRACT_ADDRESSES,
  REBALANCE_EXECUTOR_ABI,
  RebalanceStatus,
} from '../config/contracts.js'

interface Allocation {
  token: `0x${string}`
  targetWeight: bigint
  currentWeight: bigint
}

interface RebalanceStrategy {
  user: `0x${string}`
  allocations: Allocation[]
  rebalanceThreshold: bigint
  minRebalanceInterval: bigint
  lastRebalanceTime: bigint
  totalRebalances: bigint
  poolFee: number
  status: RebalanceStatus
  createdAt: bigint
  updatedAt: bigint
}

export class RebalanceExecutorService {
  private publicClient: PublicClient
  private walletClient: WalletClient
  private account: ReturnType<typeof privateKeyToAccount>
  private knownStrategies: Set<string> = new Set()

  constructor() {
    // Create account from private key
    const privateKey = config.executorPrivateKey.startsWith('0x')
      ? config.executorPrivateKey as `0x${string}`
      : `0x${config.executorPrivateKey}` as `0x${string}`

    this.account = privateKeyToAccount(privateKey)

    // Create clients
    this.publicClient = createPublicClient({
      chain: sepolia,
      transport: http(config.rpcUrl),
    })

    this.walletClient = createWalletClient({
      account: this.account,
      chain: sepolia,
      transport: http(config.rpcUrl),
    })

    console.log(`[Rebalance] Executor initialized with address: ${this.account.address}`)
  }

  /**
   * Get all strategies that need rebalancing
   */
  async getStrategiesNeedingRebalance(): Promise<{ strategyId: `0x${string}`; strategy: RebalanceStrategy }[]> {
    const strategiesNeedingRebalance: { strategyId: `0x${string}`; strategy: RebalanceStrategy }[] = []

    // For now, we iterate through known strategies
    // In production, this should use indexer or events
    for (const strategyId of this.knownStrategies) {
      try {
        const strategy = await this.publicClient.readContract({
          address: CONTRACT_ADDRESSES.rebalanceExecutor,
          abi: REBALANCE_EXECUTOR_ABI,
          functionName: 'getStrategy',
          args: [strategyId as `0x${string}`],
        }) as RebalanceStrategy

        if (strategy.status === RebalanceStatus.Active) {
          const { needed } = await this.needsRebalance(strategyId as `0x${string}`)
          if (needed) {
            strategiesNeedingRebalance.push({ strategyId: strategyId as `0x${string}`, strategy })
          }
        }
      } catch (error) {
        console.error(`[Rebalance] Error checking strategy ${strategyId}:`, error)
      }
    }

    return strategiesNeedingRebalance
  }

  /**
   * Check if a specific strategy needs rebalancing
   */
  async needsRebalance(strategyId: `0x${string}`): Promise<{ needed: boolean; reason: string }> {
    try {
      const [needed, reason] = await this.publicClient.readContract({
        address: CONTRACT_ADDRESSES.rebalanceExecutor,
        abi: REBALANCE_EXECUTOR_ABI,
        functionName: 'needsRebalance',
        args: [strategyId],
      }) as [boolean, string]

      return { needed, reason }
    } catch (error) {
      return { needed: false, reason: `Error: ${error}` }
    }
  }

  /**
   * Execute rebalance for a single strategy
   */
  async executeRebalance(strategyId: `0x${string}`): Promise<{
    success: boolean
    txHash?: `0x${string}`
    error?: string
  }> {
    console.log(`[Rebalance] Executing rebalance for ${strategyId.slice(0, 10)}...`)

    // Check if we should actually execute
    if (!config.enableExecution) {
      console.log('[Rebalance] Execution disabled (dry-run mode)')
      return { success: false, error: 'Execution disabled' }
    }

    // Verify needs rebalance
    const { needed, reason } = await this.needsRebalance(strategyId)
    if (!needed) {
      console.log(`[Rebalance] Strategy doesn't need rebalancing: ${reason}`)
      return { success: false, error: reason }
    }

    try {
      // Simulate first
      const { request } = await this.publicClient.simulateContract({
        address: CONTRACT_ADDRESSES.rebalanceExecutor,
        abi: REBALANCE_EXECUTOR_ABI,
        functionName: 'executeRebalance',
        args: [strategyId],
        account: this.account,
      })

      // Execute
      const txHash = await this.walletClient.writeContract(request)
      console.log(`[Rebalance] Transaction submitted: ${txHash}`)

      // Wait for confirmation
      const receipt = await this.publicClient.waitForTransactionReceipt({
        hash: txHash,
        confirmations: 1,
      })

      if (receipt.status === 'success') {
        console.log(`[Rebalance] Strategy ${strategyId.slice(0, 10)} rebalanced successfully!`)
        return { success: true, txHash }
      } else {
        console.error(`[Rebalance] Transaction reverted: ${txHash}`)
        return { success: false, txHash, error: 'Transaction reverted' }
      }
    } catch (error: any) {
      console.error(`[Rebalance] Execution failed:`, error.message)
      return { success: false, error: error.message }
    }
  }

  /**
   * Add a strategy to monitor
   */
  addStrategy(strategyId: string): void {
    this.knownStrategies.add(strategyId)
    console.log(`[Rebalance] Added strategy to monitor: ${strategyId.slice(0, 10)}...`)
  }

  /**
   * Remove a strategy from monitoring
   */
  removeStrategy(strategyId: string): void {
    this.knownStrategies.delete(strategyId)
    console.log(`[Rebalance] Removed strategy from monitor: ${strategyId.slice(0, 10)}...`)
  }

  /**
   * Get portfolio value for a strategy
   */
  async getPortfolioValue(strategyId: `0x${string}`): Promise<bigint> {
    try {
      const value = await this.publicClient.readContract({
        address: CONTRACT_ADDRESSES.rebalanceExecutor,
        abi: REBALANCE_EXECUTOR_ABI,
        functionName: 'getPortfolioValue',
        args: [strategyId],
      }) as bigint

      return value
    } catch (error) {
      console.error(`[Rebalance] Error getting portfolio value:`, error)
      return 0n
    }
  }

  /**
   * Run the executor - check and rebalance all strategies that need it
   */
  async run(): Promise<void> {
    console.log('\n[Rebalance] === Starting Rebalance Executor Run ===')
    console.log(`[Rebalance] Time: ${new Date().toISOString()}`)
    console.log(`[Rebalance] Monitoring ${this.knownStrategies.size} strategies`)

    const strategies = await this.getStrategiesNeedingRebalance()

    if (strategies.length === 0) {
      console.log('[Rebalance] No strategies need rebalancing')
      return
    }

    console.log(`[Rebalance] Found ${strategies.length} strategies needing rebalance`)

    let successCount = 0
    let failCount = 0

    for (const { strategyId, strategy } of strategies) {
      const result = await this.executeRebalance(strategyId)

      if (result.success) {
        successCount++
        console.log(
          `[Rebalance] Successfully rebalanced strategy for ${strategy.user.slice(0, 8)}... ` +
          `(${strategy.allocations.length} tokens)`
        )
      } else {
        failCount++
        console.error(`[Rebalance] Failed to rebalance strategy: ${result.error}`)
      }

      // Small delay between executions
      await new Promise((resolve) => setTimeout(resolve, 1000))
    }

    console.log(`[Rebalance] === Run Complete ===`)
    console.log(`[Rebalance] Success: ${successCount}, Failed: ${failCount}`)
  }

  /**
   * Get executor wallet balance
   */
  async getBalance(): Promise<bigint> {
    return this.publicClient.getBalance({ address: this.account.address })
  }

  /**
   * Get executor wallet address
   */
  getAddress(): `0x${string}` {
    return this.account.address
  }
}
