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
  SUBSCRIPTION_MANAGER_ABI,
  SubscriptionStatus,
} from '../config/contracts.js'
import { indexerClient } from './indexerClient.js'

interface Subscription {
  subscriptionId: `0x${string}`
  subscriber: `0x${string}`
  recipient: `0x${string}`
  token: `0x${string}`
  amount: bigint
  billingPeriod: number
  nextPaymentTime: bigint
  paymentsCompleted: bigint
  maxPayments: bigint
  status: SubscriptionStatus
  createdAt: bigint
  cancelledAt: bigint
}

export class SubscriptionExecutorService {
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

    console.log(`[SUB] Executor initialized with address: ${this.account.address}`)
  }

  /**
   * Get subscription details
   */
  async getSubscription(subscriptionId: `0x${string}`): Promise<Subscription | null> {
    try {
      const subscription = await this.publicClient.readContract({
        address: CONTRACT_ADDRESSES.subscriptionManager,
        abi: SUBSCRIPTION_MANAGER_ABI,
        functionName: 'getSubscription',
        args: [subscriptionId],
      }) as Subscription

      return subscription
    } catch (error) {
      console.error(`[SUB] Error fetching subscription ${subscriptionId}:`, error)
      return null
    }
  }

  /**
   * Check if a subscription payment can be executed
   */
  async canExecutePayment(subscriptionId: `0x${string}`): Promise<{ canPay: boolean; reason: string }> {
    try {
      const [canPay, reason] = await this.publicClient.readContract({
        address: CONTRACT_ADDRESSES.subscriptionManager,
        abi: SUBSCRIPTION_MANAGER_ABI,
        functionName: 'canExecutePayment',
        args: [subscriptionId],
      }) as [boolean, string]

      return { canPay, reason }
    } catch (error) {
      return { canPay: false, reason: `Error: ${error}` }
    }
  }

  /**
   * Execute a subscription payment
   */
  async executePayment(subscriptionId: `0x${string}`): Promise<{
    success: boolean
    txHash?: `0x${string}`
    error?: string
  }> {
    console.log(`[SUB] Executing payment for subscription ${subscriptionId.slice(0, 10)}...`)

    // Check if we should actually execute
    if (!config.enableExecution) {
      console.log('[SUB] Execution disabled (dry-run mode)')
      return { success: false, error: 'Execution disabled' }
    }

    // Verify can execute
    const { canPay, reason } = await this.canExecutePayment(subscriptionId)
    if (!canPay) {
      console.log(`[SUB] Cannot execute payment: ${reason}`)
      return { success: false, error: reason }
    }

    try {
      // Simulate first
      const { request } = await this.publicClient.simulateContract({
        address: CONTRACT_ADDRESSES.subscriptionManager,
        abi: SUBSCRIPTION_MANAGER_ABI,
        functionName: 'executePayment',
        args: [subscriptionId],
        account: this.account,
      })

      // Execute
      const txHash = await this.walletClient.writeContract(request)
      console.log(`[SUB] Transaction submitted: ${txHash}`)

      // Wait for confirmation
      const receipt = await this.publicClient.waitForTransactionReceipt({
        hash: txHash,
        confirmations: 1,
      })

      if (receipt.status === 'success') {
        console.log(`[SUB] Payment ${subscriptionId.slice(0, 10)} executed successfully!`)
        return { success: true, txHash }
      } else {
        console.error(`[SUB] Transaction reverted: ${txHash}`)
        return { success: false, txHash, error: 'Transaction reverted' }
      }
    } catch (error: any) {
      console.error(`[SUB] Execution failed:`, error.message)
      return { success: false, error: error.message }
    }
  }

  /**
   * Get all due subscriptions from indexer
   */
  async getDueSubscriptionsFromIndexer(): Promise<{ subscriptionId: `0x${string}`; subscription: Subscription }[]> {
    const dueSubscriptions: { subscriptionId: `0x${string}`; subscription: Subscription }[] = []

    try {
      const indexerSubs = await indexerClient.getDueSubscriptions()
      console.log(`[SUB] Found ${indexerSubs.length} due subscriptions from indexer`)

      for (const sub of indexerSubs) {
        const subscription = await this.getSubscription(sub.id as `0x${string}`)
        if (subscription) {
          dueSubscriptions.push({
            subscriptionId: sub.id as `0x${string}`,
            subscription,
          })
        }
      }
    } catch (error) {
      console.error('[SUB] Error getting due subscriptions from indexer:', error)
    }

    return dueSubscriptions
  }

  /**
   * Get due subscriptions for a specific subscriber
   * Note: In a production system, you'd want to maintain a list of all subscribers
   * or use an indexer to track subscriptions
   */
  async getDueSubscriptionsForSubscriber(
    subscriber: `0x${string}`
  ): Promise<{ subscriptionId: `0x${string}`; subscription: Subscription }[]> {
    const now = BigInt(Math.floor(Date.now() / 1000))
    const dueSubscriptions: { subscriptionId: `0x${string}`; subscription: Subscription }[] = []

    try {
      const subscriptionIds = await this.publicClient.readContract({
        address: CONTRACT_ADDRESSES.subscriptionManager,
        abi: SUBSCRIPTION_MANAGER_ABI,
        functionName: 'getSubscriberSubscriptions',
        args: [subscriber],
      }) as `0x${string}`[]

      for (const subscriptionId of subscriptionIds) {
        const subscription = await this.getSubscription(subscriptionId)

        if (
          subscription &&
          subscription.status === SubscriptionStatus.Active &&
          subscription.nextPaymentTime <= now &&
          (subscription.maxPayments === 0n ||
            subscription.paymentsCompleted < subscription.maxPayments)
        ) {
          dueSubscriptions.push({ subscriptionId, subscription })
        }
      }
    } catch (error) {
      console.error(`[SUB] Error getting due subscriptions for ${subscriber}:`, error)
    }

    return dueSubscriptions
  }

  /**
   * Run the executor - uses indexer first, falls back to known subscribers list
   */
  async run(knownSubscribers: `0x${string}`[] = []): Promise<void> {
    console.log('\n[SUB] === Starting Subscription Executor Run ===')
    console.log(`[SUB] Time: ${new Date().toISOString()}`)

    let dueSubscriptions: { subscriptionId: `0x${string}`; subscription: Subscription }[] = []

    // Try indexer first
    if (this.useIndexer) {
      try {
        const isHealthy = await indexerClient.isHealthy()
        if (isHealthy) {
          dueSubscriptions = await this.getDueSubscriptionsFromIndexer()
        }
      } catch (error) {
        console.warn('[SUB] Indexer unavailable, falling back to known subscribers:', error)
        this.useIndexer = false
      }
    }

    // Fallback to known subscribers if indexer unavailable or returned nothing
    if (dueSubscriptions.length === 0 && knownSubscribers.length > 0) {
      console.log(`[SUB] Checking ${knownSubscribers.length} known subscribers`)
      for (const subscriber of knownSubscribers) {
        const subs = await this.getDueSubscriptionsForSubscriber(subscriber)
        dueSubscriptions.push(...subs)
      }
    }

    if (dueSubscriptions.length === 0) {
      console.log('[SUB] No subscriptions due for payment')
      return
    }

    console.log(`[SUB] Found ${dueSubscriptions.length} subscriptions due for payment`)

    let successCount = 0
    let failCount = 0

    for (const { subscriptionId, subscription } of dueSubscriptions) {
      const result = await this.executePayment(subscriptionId)

      if (result.success) {
        successCount++
        console.log(
          `[SUB] Successfully executed payment: ` +
          `${formatUnits(subscription.amount, 6)} USDC to ${subscription.recipient.slice(0, 8)}...`
        )
      } else {
        failCount++
        console.error(`[SUB] Failed to execute payment: ${result.error}`)
      }

      // Small delay between executions
      await new Promise((resolve) => setTimeout(resolve, 1000))
    }

    console.log(`[SUB] === Run Complete ===`)
    console.log(`[SUB] Success: ${successCount}, Failed: ${failCount}`)
  }
}
