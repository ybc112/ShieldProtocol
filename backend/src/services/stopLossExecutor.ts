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
  STOP_LOSS_EXECUTOR_ABI,
  StopLossStatus,
  StopLossType,
} from '../config/contracts.js'

interface StopLossStrategy {
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

export class StopLossExecutorService {
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

    console.log(`[StopLoss] Executor initialized with address: ${this.account.address}`)
  }

  /**
   * Get all strategies that should be triggered
   */
  async getStrategiesToTrigger(): Promise<{ strategyId: `0x${string}`; strategy: StopLossStrategy; currentPrice: bigint }[]> {
    const strategiesToTrigger: { strategyId: `0x${string}`; strategy: StopLossStrategy; currentPrice: bigint }[] = []

    for (const strategyId of this.knownStrategies) {
      try {
        const strategy = await this.publicClient.readContract({
          address: CONTRACT_ADDRESSES.stopLossExecutor,
          abi: STOP_LOSS_EXECUTOR_ABI,
          functionName: 'getStrategy',
          args: [strategyId as `0x${string}`],
        }) as StopLossStrategy

        if (strategy.status === StopLossStatus.Active) {
          const { triggered, currentPrice } = await this.shouldTrigger(strategyId as `0x${string}`)
          if (triggered) {
            strategiesToTrigger.push({ strategyId: strategyId as `0x${string}`, strategy, currentPrice })
          }
        }
      } catch (error) {
        console.error(`[StopLoss] Error checking strategy ${strategyId}:`, error)
      }
    }

    return strategiesToTrigger
  }

  /**
   * Check if a specific strategy should be triggered
   */
  async shouldTrigger(strategyId: `0x${string}`): Promise<{ triggered: boolean; currentPrice: bigint }> {
    try {
      const [triggered, currentPrice] = await this.publicClient.readContract({
        address: CONTRACT_ADDRESSES.stopLossExecutor,
        abi: STOP_LOSS_EXECUTOR_ABI,
        functionName: 'shouldTrigger',
        args: [strategyId],
      }) as [boolean, bigint]

      return { triggered, currentPrice }
    } catch (error) {
      return { triggered: false, currentPrice: 0n }
    }
  }

  /**
   * Get current trigger price for a strategy
   */
  async getCurrentTriggerPrice(strategyId: `0x${string}`): Promise<bigint> {
    try {
      const price = await this.publicClient.readContract({
        address: CONTRACT_ADDRESSES.stopLossExecutor,
        abi: STOP_LOSS_EXECUTOR_ABI,
        functionName: 'getCurrentTriggerPrice',
        args: [strategyId],
      }) as bigint

      return price
    } catch (error) {
      console.error(`[StopLoss] Error getting trigger price:`, error)
      return 0n
    }
  }

  /**
   * Execute stop-loss for a single strategy
   */
  async executeStopLoss(strategyId: `0x${string}`): Promise<{
    success: boolean
    txHash?: `0x${string}`
    executed?: boolean
    error?: string
  }> {
    console.log(`[StopLoss] Executing stop-loss for ${strategyId.slice(0, 10)}...`)

    // Check if we should actually execute
    if (!config.enableExecution) {
      console.log('[StopLoss] Execution disabled (dry-run mode)')
      return { success: false, error: 'Execution disabled' }
    }

    // Verify should trigger
    const { triggered, currentPrice } = await this.shouldTrigger(strategyId)
    if (!triggered) {
      console.log(`[StopLoss] Strategy should not be triggered at current price: ${currentPrice}`)
      return { success: false, error: 'Not triggered' }
    }

    try {
      // Simulate first
      const { request } = await this.publicClient.simulateContract({
        address: CONTRACT_ADDRESSES.stopLossExecutor,
        abi: STOP_LOSS_EXECUTOR_ABI,
        functionName: 'checkAndExecute',
        args: [strategyId],
        account: this.account,
      })

      // Execute
      const txHash = await this.walletClient.writeContract(request)
      console.log(`[StopLoss] Transaction submitted: ${txHash}`)

      // Wait for confirmation
      const receipt = await this.publicClient.waitForTransactionReceipt({
        hash: txHash,
        confirmations: 1,
      })

      if (receipt.status === 'success') {
        console.log(`[StopLoss] Strategy ${strategyId.slice(0, 10)} executed successfully!`)

        // Remove from monitoring since it's now executed
        this.knownStrategies.delete(strategyId)

        return { success: true, txHash, executed: true }
      } else {
        console.error(`[StopLoss] Transaction reverted: ${txHash}`)
        return { success: false, txHash, error: 'Transaction reverted' }
      }
    } catch (error: any) {
      console.error(`[StopLoss] Execution failed:`, error.message)
      return { success: false, error: error.message }
    }
  }

  /**
   * Add a strategy to monitor
   */
  addStrategy(strategyId: string): void {
    this.knownStrategies.add(strategyId)
    console.log(`[StopLoss] Added strategy to monitor: ${strategyId.slice(0, 10)}...`)
  }

  /**
   * Remove a strategy from monitoring
   */
  removeStrategy(strategyId: string): void {
    this.knownStrategies.delete(strategyId)
    console.log(`[StopLoss] Removed strategy from monitor: ${strategyId.slice(0, 10)}...`)
  }

  /**
   * Get stop loss type name
   */
  private getStopLossTypeName(type: StopLossType): string {
    switch (type) {
      case StopLossType.FixedPrice:
        return 'Fixed Price'
      case StopLossType.Percentage:
        return 'Percentage'
      case StopLossType.TrailingStop:
        return 'Trailing Stop'
      default:
        return 'Unknown'
    }
  }

  /**
   * Run the executor - check and execute all stop-loss strategies that should trigger
   */
  async run(): Promise<void> {
    console.log('\n[StopLoss] === Starting Stop-Loss Executor Run ===')
    console.log(`[StopLoss] Time: ${new Date().toISOString()}`)
    console.log(`[StopLoss] Monitoring ${this.knownStrategies.size} strategies`)

    const strategies = await this.getStrategiesToTrigger()

    if (strategies.length === 0) {
      console.log('[StopLoss] No strategies should be triggered')
      return
    }

    console.log(`[StopLoss] Found ${strategies.length} strategies to execute`)

    let successCount = 0
    let failCount = 0

    for (const { strategyId, strategy, currentPrice } of strategies) {
      console.log(
        `[StopLoss] Processing ${this.getStopLossTypeName(strategy.stopLossType)} strategy ` +
        `for ${strategy.user.slice(0, 8)}... (current price: ${formatUnits(currentPrice, 6)})`
      )

      const result = await this.executeStopLoss(strategyId)

      if (result.success) {
        successCount++
        console.log(
          `[StopLoss] Successfully executed stop-loss for ${strategy.user.slice(0, 8)}... ` +
          `(${formatUnits(strategy.amount, 18)} tokens)`
        )
      } else {
        failCount++
        console.error(`[StopLoss] Failed to execute stop-loss: ${result.error}`)
      }

      // Small delay between executions
      await new Promise((resolve) => setTimeout(resolve, 1000))
    }

    console.log(`[StopLoss] === Run Complete ===`)
    console.log(`[StopLoss] Success: ${successCount}, Failed: ${failCount}`)
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
