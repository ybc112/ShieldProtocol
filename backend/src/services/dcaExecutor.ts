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
  DCA_EXECUTOR_ABI,
  StrategyStatus,
} from '../config/contracts.js'
import { indexerClient } from './indexerClient.js'

interface Strategy {
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

export class DCAExecutorService {
  private publicClient: PublicClient
  private walletClient: WalletClient
  private account: ReturnType<typeof privateKeyToAccount>
  private useIndexer: boolean = true

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

    console.log(`[DCA] Executor initialized with address: ${this.account.address}`)
  }

  /**
   * Get all strategies that are due for execution
   * First tries indexer, falls back to contract if unavailable
   */
  async getDueStrategies(): Promise<{ strategyId: `0x${string}`; strategy: Strategy }[]> {
    // Try indexer first
    if (this.useIndexer) {
      try {
        const isHealthy = await indexerClient.isHealthy()
        if (isHealthy) {
          const indexerStrategies = await indexerClient.getActiveStrategies()
          console.log(`[DCA] Found ${indexerStrategies.length} strategies from indexer`)

          // Convert indexer format to contract format
          const strategies: { strategyId: `0x${string}`; strategy: Strategy }[] = []
          for (const s of indexerStrategies) {
            try {
              // Fetch fresh data from contract for execution
              const strategy = await this.publicClient.readContract({
                address: CONTRACT_ADDRESSES.dcaExecutor,
                abi: DCA_EXECUTOR_ABI,
                functionName: 'getStrategy',
                args: [s.id as `0x${string}`],
              }) as Strategy

              strategies.push({ strategyId: s.id as `0x${string}`, strategy })
            } catch (error) {
              console.error(`[DCA] Error fetching strategy ${s.id} from contract:`, error)
            }
          }
          return strategies
        }
      } catch (error) {
        console.warn('[DCA] Indexer unavailable, falling back to contract:', error)
        this.useIndexer = false
      }
    }

    // Fallback to contract
    return this.getDueStrategiesFromContract()
  }

  /**
   * Get strategies directly from contract (fallback method)
   */
  private async getDueStrategiesFromContract(): Promise<{ strategyId: `0x${string}`; strategy: Strategy }[]> {
    const dueStrategies: { strategyId: `0x${string}`; strategy: Strategy }[] = []

    try {
      let startIndex = 0n
      const limit = 50n
      let hasMore = true

      while (hasMore) {
        const [strategyIds, nextIndex] = await this.publicClient.readContract({
          address: CONTRACT_ADDRESSES.dcaExecutor,
          abi: DCA_EXECUTOR_ABI,
          functionName: 'getPendingStrategies',
          args: [startIndex, limit],
        }) as [readonly `0x${string}`[], bigint]

        console.log(`[DCA] Found ${strategyIds.length} pending strategies from contract (batch from index ${startIndex})`)

        for (const strategyId of strategyIds) {
          try {
            const strategy = await this.publicClient.readContract({
              address: CONTRACT_ADDRESSES.dcaExecutor,
              abi: DCA_EXECUTOR_ABI,
              functionName: 'getStrategy',
              args: [strategyId],
            }) as Strategy

            dueStrategies.push({ strategyId, strategy })
          } catch (error) {
            console.error(`[DCA] Error fetching strategy ${strategyId}:`, error)
          }
        }

        if (nextIndex === 0n || strategyIds.length === 0) {
          hasMore = false
        } else {
          startIndex = nextIndex
        }
      }
    } catch (error) {
      console.error('[DCA] Error getting due strategies from contract:', error)
    }

    return dueStrategies
  }

  /**
   * Check if a specific strategy can be executed
   */
  async canExecute(strategyId: `0x${string}`): Promise<{ canExecute: boolean; reason: string }> {
    try {
      const [canExec, reason] = await this.publicClient.readContract({
        address: CONTRACT_ADDRESSES.dcaExecutor,
        abi: DCA_EXECUTOR_ABI,
        functionName: 'canExecute',
        args: [strategyId],
      }) as [boolean, string]

      return { canExecute: canExec, reason }
    } catch (error) {
      return { canExecute: false, reason: `Error: ${error}` }
    }
  }

  /**
   * Execute a single DCA strategy
   */
  async executeStrategy(strategyId: `0x${string}`): Promise<{
    success: boolean
    txHash?: `0x${string}`
    amountOut?: bigint
    error?: string
  }> {
    console.log(`[DCA] Executing strategy ${strategyId.slice(0, 10)}...`)

    // Check if we should actually execute
    if (!config.enableExecution) {
      console.log('[DCA] Execution disabled (dry-run mode)')
      return { success: false, error: 'Execution disabled' }
    }

    // Verify can execute
    const { canExecute, reason } = await this.canExecute(strategyId)
    if (!canExecute) {
      console.log(`[DCA] Cannot execute: ${reason}`)
      return { success: false, error: reason }
    }

    try {
      // Simulate first
      const { request } = await this.publicClient.simulateContract({
        address: CONTRACT_ADDRESSES.dcaExecutor,
        abi: DCA_EXECUTOR_ABI,
        functionName: 'executeDCA',
        args: [strategyId],
        account: this.account,
      })

      // Execute
      const txHash = await this.walletClient.writeContract(request)
      console.log(`[DCA] Transaction submitted: ${txHash}`)

      // Wait for confirmation
      const receipt = await this.publicClient.waitForTransactionReceipt({
        hash: txHash,
        confirmations: 1,
      })

      if (receipt.status === 'success') {
        console.log(`[DCA] Strategy ${strategyId.slice(0, 10)} executed successfully!`)
        return { success: true, txHash }
      } else {
        console.error(`[DCA] Transaction reverted: ${txHash}`)
        return { success: false, txHash, error: 'Transaction reverted' }
      }
    } catch (error: any) {
      console.error(`[DCA] Execution failed:`, error.message)
      return { success: false, error: error.message }
    }
  }

  /**
   * Run the executor - check and execute all due strategies
   */
  async run(): Promise<void> {
    console.log('\n[DCA] === Starting DCA Executor Run ===')
    console.log(`[DCA] Time: ${new Date().toISOString()}`)

    const dueStrategies = await this.getDueStrategies()

    if (dueStrategies.length === 0) {
      console.log('[DCA] No strategies due for execution')
      return
    }

    console.log(`[DCA] Found ${dueStrategies.length} strategies due for execution`)

    let successCount = 0
    let failCount = 0

    for (const { strategyId, strategy } of dueStrategies) {
      const result = await this.executeStrategy(strategyId)

      if (result.success) {
        successCount++
        console.log(
          `[DCA] Successfully executed strategy for ${strategy.user.slice(0, 8)}... ` +
          `(${formatUnits(strategy.amountPerExecution, 6)} USDC)`
        )
      } else {
        failCount++
        console.error(`[DCA] Failed to execute strategy: ${result.error}`)
      }

      // Small delay between executions to avoid rate limiting
      await new Promise((resolve) => setTimeout(resolve, 1000))
    }

    console.log(`[DCA] === Run Complete ===`)
    console.log(`[DCA] Success: ${successCount}, Failed: ${failCount}`)
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
