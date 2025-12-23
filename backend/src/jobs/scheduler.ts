import cron from 'node-cron'
import { config } from '../config/index.js'
import { DCAExecutorService } from '../services/dcaExecutor.js'
import { SubscriptionExecutorService } from '../services/subscriptionExecutor.js'
import { RebalanceExecutorService } from '../services/rebalanceExecutor.js'
import { StopLossExecutorService } from '../services/stopLossExecutor.js'
import { MonitoringServer } from '../server/index.js'

export class Scheduler {
  private dcaExecutor: DCAExecutorService
  private subscriptionExecutor: SubscriptionExecutorService
  private rebalanceExecutor: RebalanceExecutorService
  private stopLossExecutor: StopLossExecutorService
  private dcaTask: cron.ScheduledTask | null = null
  private subscriptionTask: cron.ScheduledTask | null = null
  private rebalanceTask: cron.ScheduledTask | null = null
  private stopLossTask: cron.ScheduledTask | null = null
  private monitoringServer: MonitoringServer | null = null

  // Known subscribers - in production, this should come from an indexer
  private knownSubscribers: `0x${string}`[] = []

  constructor() {
    this.dcaExecutor = new DCAExecutorService()
    this.subscriptionExecutor = new SubscriptionExecutorService()
    this.rebalanceExecutor = new RebalanceExecutorService()
    this.stopLossExecutor = new StopLossExecutorService()
  }

  /**
   * Get the DCA executor instance (for monitoring)
   */
  getDCAExecutor(): DCAExecutorService {
    return this.dcaExecutor
  }

  /**
   * Get the subscription executor instance (for monitoring)
   */
  getSubscriptionExecutor(): SubscriptionExecutorService {
    return this.subscriptionExecutor
  }

  /**
   * Get the rebalance executor instance (for monitoring)
   */
  getRebalanceExecutor(): RebalanceExecutorService {
    return this.rebalanceExecutor
  }

  /**
   * Get the stop-loss executor instance (for monitoring)
   */
  getStopLossExecutor(): StopLossExecutorService {
    return this.stopLossExecutor
  }

  /**
   * Add a subscriber to monitor
   */
  addSubscriber(address: `0x${string}`) {
    if (!this.knownSubscribers.includes(address)) {
      this.knownSubscribers.push(address)
      console.log(`[Scheduler] Added subscriber: ${address}`)
    }
  }

  /**
   * Add a rebalance strategy to monitor
   */
  addRebalanceStrategy(strategyId: string) {
    this.rebalanceExecutor.addStrategy(strategyId)
  }

  /**
   * Add a stop-loss strategy to monitor
   */
  addStopLossStrategy(strategyId: string) {
    this.stopLossExecutor.addStrategy(strategyId)
  }

  /**
   * Start the DCA scheduler
   */
  startDCAScheduler(): void {
    if (this.dcaTask) {
      console.log('[Scheduler] DCA scheduler already running')
      return
    }

    console.log(`[Scheduler] Starting DCA scheduler with cron: ${config.cronSchedule}`)

    this.dcaTask = cron.schedule(config.cronSchedule, async () => {
      try {
        await this.dcaExecutor.run()
      } catch (error) {
        console.error('[Scheduler] DCA execution error:', error)
      }
    })

    console.log('[Scheduler] DCA scheduler started')
  }

  /**
   * Start the Subscription scheduler
   */
  startSubscriptionScheduler(): void {
    if (this.subscriptionTask) {
      console.log('[Scheduler] Subscription scheduler already running')
      return
    }

    // Run subscription check every 10 minutes
    const subscriptionSchedule = '*/10 * * * *'
    console.log(`[Scheduler] Starting Subscription scheduler with cron: ${subscriptionSchedule}`)

    this.subscriptionTask = cron.schedule(subscriptionSchedule, async () => {
      try {
        await this.subscriptionExecutor.run(this.knownSubscribers)
      } catch (error) {
        console.error('[Scheduler] Subscription execution error:', error)
      }
    })

    console.log('[Scheduler] Subscription scheduler started')
  }

  /**
   * Start the Rebalance scheduler
   */
  startRebalanceScheduler(): void {
    if (this.rebalanceTask) {
      console.log('[Scheduler] Rebalance scheduler already running')
      return
    }

    // Run rebalance check every 30 minutes
    const rebalanceSchedule = '*/30 * * * *'
    console.log(`[Scheduler] Starting Rebalance scheduler with cron: ${rebalanceSchedule}`)

    this.rebalanceTask = cron.schedule(rebalanceSchedule, async () => {
      try {
        await this.rebalanceExecutor.run()
      } catch (error) {
        console.error('[Scheduler] Rebalance execution error:', error)
      }
    })

    console.log('[Scheduler] Rebalance scheduler started')
  }

  /**
   * Start the Stop-Loss scheduler
   */
  startStopLossScheduler(): void {
    if (this.stopLossTask) {
      console.log('[Scheduler] Stop-Loss scheduler already running')
      return
    }

    // Run stop-loss check every 2 minutes (more frequent for price monitoring)
    const stopLossSchedule = '*/2 * * * *'
    console.log(`[Scheduler] Starting Stop-Loss scheduler with cron: ${stopLossSchedule}`)

    this.stopLossTask = cron.schedule(stopLossSchedule, async () => {
      try {
        await this.stopLossExecutor.run()
      } catch (error) {
        console.error('[Scheduler] Stop-Loss execution error:', error)
      }
    })

    console.log('[Scheduler] Stop-Loss scheduler started')
  }

  /**
   * Start all schedulers
   */
  start(): void {
    console.log('\n========================================')
    console.log('  Shield Protocol Execution Service')
    console.log('========================================\n')

    this.startDCAScheduler()
    this.startSubscriptionScheduler()
    this.startRebalanceScheduler()
    this.startStopLossScheduler()
    this.startMonitoringServer()

    console.log('\n[Scheduler] All schedulers started')
    console.log('[Scheduler] Waiting for next execution...\n')
  }

  /**
   * Start the monitoring HTTP server
   */
  startMonitoringServer(port: number = 3001): void {
    if (this.monitoringServer) {
      console.log('[Scheduler] Monitoring server already running')
      return
    }

    this.monitoringServer = new MonitoringServer(
      this.dcaExecutor,
      this.subscriptionExecutor,
      port
    )
    this.monitoringServer.setSchedulerStatus(true)
    this.monitoringServer.start()
  }

  /**
   * Stop all schedulers
   */
  stop(): void {
    if (this.dcaTask) {
      this.dcaTask.stop()
      this.dcaTask = null
      console.log('[Scheduler] DCA scheduler stopped')
    }

    if (this.subscriptionTask) {
      this.subscriptionTask.stop()
      this.subscriptionTask = null
      console.log('[Scheduler] Subscription scheduler stopped')
    }

    if (this.rebalanceTask) {
      this.rebalanceTask.stop()
      this.rebalanceTask = null
      console.log('[Scheduler] Rebalance scheduler stopped')
    }

    if (this.stopLossTask) {
      this.stopLossTask.stop()
      this.stopLossTask = null
      console.log('[Scheduler] Stop-Loss scheduler stopped')
    }

    if (this.monitoringServer) {
      this.monitoringServer.setSchedulerStatus(false)
      this.monitoringServer.stop()
      this.monitoringServer = null
    }
  }

  /**
   * Run immediate execution (for testing)
   */
  async runNow(): Promise<void> {
    console.log('[Scheduler] Running immediate execution...')
    await this.dcaExecutor.run()
    await this.subscriptionExecutor.run(this.knownSubscribers)
    await this.rebalanceExecutor.run()
    await this.stopLossExecutor.run()
  }

  /**
   * Get executor status
   */
  async getStatus(): Promise<{
    dcaExecutorBalance: string
    isRunning: boolean
    knownSubscribers: number
    activeSchedulers: string[]
  }> {
    const balance = await this.dcaExecutor.getBalance()

    const activeSchedulers: string[] = []
    if (this.dcaTask) activeSchedulers.push('DCA')
    if (this.subscriptionTask) activeSchedulers.push('Subscription')
    if (this.rebalanceTask) activeSchedulers.push('Rebalance')
    if (this.stopLossTask) activeSchedulers.push('StopLoss')

    return {
      dcaExecutorBalance: `${Number(balance) / 1e18} ETH`,
      isRunning: activeSchedulers.length > 0,
      knownSubscribers: this.knownSubscribers.length,
      activeSchedulers,
    }
  }
}
