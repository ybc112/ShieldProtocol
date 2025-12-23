import http from 'http'
import { config } from '../config/index.js'
import { indexerClient } from '../services/indexerClient.js'
import { DCAExecutorService } from '../services/dcaExecutor.js'
import { SubscriptionExecutorService } from '../services/subscriptionExecutor.js'

interface ServerStatus {
  status: 'healthy' | 'degraded' | 'unhealthy'
  timestamp: string
  uptime: number
  version: string
  services: {
    scheduler: boolean
    indexer: boolean
    rpc: boolean
  }
  executorWallet: {
    address: string
    balance: string
  }
  stats: {
    totalDCAStrategies: number
    totalSubscriptions: number
    pendingDCAExecutions: number
    pendingSubscriptions: number
  }
}

export class MonitoringServer {
  private server: http.Server | null = null
  private startTime: number
  private dcaExecutor: DCAExecutorService
  private subscriptionExecutor: SubscriptionExecutorService
  private schedulerRunning: boolean = false
  private port: number

  constructor(
    dcaExecutor: DCAExecutorService,
    subscriptionExecutor: SubscriptionExecutorService,
    port: number = 3001
  ) {
    this.startTime = Date.now()
    this.dcaExecutor = dcaExecutor
    this.subscriptionExecutor = subscriptionExecutor
    this.port = port
  }

  setSchedulerStatus(running: boolean) {
    this.schedulerRunning = running
  }

  async getStatus(): Promise<ServerStatus> {
    const now = Date.now()
    const uptime = Math.floor((now - this.startTime) / 1000)

    // Check indexer health
    let indexerHealthy = false
    let globalStats = null
    try {
      indexerHealthy = await indexerClient.isHealthy()
      if (indexerHealthy) {
        globalStats = await indexerClient.getGlobalStats()
      }
    } catch {
      indexerHealthy = false
    }

    // Check RPC health and get wallet balance
    let rpcHealthy = false
    let walletBalance = '0'
    let walletAddress = ''
    try {
      const balance = await this.dcaExecutor.getBalance()
      walletBalance = `${Number(balance) / 1e18} ETH`
      walletAddress = this.dcaExecutor.getAddress()
      rpcHealthy = true
    } catch {
      rpcHealthy = false
    }

    // Get pending executions
    let pendingDCA = 0
    let pendingSubscriptions = 0
    try {
      if (indexerHealthy) {
        const activeStrategies = await indexerClient.getActiveStrategies()
        pendingDCA = activeStrategies.length

        const dueSubscriptions = await indexerClient.getDueSubscriptions()
        pendingSubscriptions = dueSubscriptions.length
      }
    } catch {
      // Ignore errors
    }

    // Determine overall status
    let status: 'healthy' | 'degraded' | 'unhealthy' = 'healthy'
    if (!rpcHealthy) {
      status = 'unhealthy'
    } else if (!indexerHealthy || !this.schedulerRunning) {
      status = 'degraded'
    }

    return {
      status,
      timestamp: new Date().toISOString(),
      uptime,
      version: '1.0.0',
      services: {
        scheduler: this.schedulerRunning,
        indexer: indexerHealthy,
        rpc: rpcHealthy,
      },
      executorWallet: {
        address: walletAddress,
        balance: walletBalance,
      },
      stats: {
        totalDCAStrategies: globalStats?.totalDCAStrategies || 0,
        totalSubscriptions: globalStats?.totalSubscriptions || 0,
        pendingDCAExecutions: pendingDCA,
        pendingSubscriptions: pendingSubscriptions,
      },
    }
  }

  start(): void {
    this.server = http.createServer(async (req, res) => {
      // Enable CORS
      res.setHeader('Access-Control-Allow-Origin', '*')
      res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS')
      res.setHeader('Access-Control-Allow-Headers', 'Content-Type')

      if (req.method === 'OPTIONS') {
        res.writeHead(204)
        res.end()
        return
      }

      const url = req.url || '/'

      try {
        if (url === '/health' || url === '/') {
          const status = await this.getStatus()
          const statusCode = status.status === 'healthy' ? 200 : status.status === 'degraded' ? 200 : 503
          res.writeHead(statusCode, { 'Content-Type': 'application/json' })
          res.end(JSON.stringify(status, null, 2))
        } else if (url === '/ready') {
          // Readiness probe - check if we can accept traffic
          const status = await this.getStatus()
          if (status.services.rpc) {
            res.writeHead(200, { 'Content-Type': 'application/json' })
            res.end(JSON.stringify({ ready: true }))
          } else {
            res.writeHead(503, { 'Content-Type': 'application/json' })
            res.end(JSON.stringify({ ready: false, reason: 'RPC not available' }))
          }
        } else if (url === '/live') {
          // Liveness probe - just check if the server is responding
          res.writeHead(200, { 'Content-Type': 'application/json' })
          res.end(JSON.stringify({ alive: true, timestamp: new Date().toISOString() }))
        } else if (url === '/metrics') {
          // Prometheus-style metrics
          const status = await this.getStatus()
          const metrics = [
            `# HELP shield_uptime_seconds Service uptime in seconds`,
            `# TYPE shield_uptime_seconds gauge`,
            `shield_uptime_seconds ${status.uptime}`,
            ``,
            `# HELP shield_scheduler_running Whether the scheduler is running`,
            `# TYPE shield_scheduler_running gauge`,
            `shield_scheduler_running ${status.services.scheduler ? 1 : 0}`,
            ``,
            `# HELP shield_indexer_healthy Whether the indexer is healthy`,
            `# TYPE shield_indexer_healthy gauge`,
            `shield_indexer_healthy ${status.services.indexer ? 1 : 0}`,
            ``,
            `# HELP shield_rpc_healthy Whether the RPC is healthy`,
            `# TYPE shield_rpc_healthy gauge`,
            `shield_rpc_healthy ${status.services.rpc ? 1 : 0}`,
            ``,
            `# HELP shield_pending_dca_executions Number of DCA strategies pending execution`,
            `# TYPE shield_pending_dca_executions gauge`,
            `shield_pending_dca_executions ${status.stats.pendingDCAExecutions}`,
            ``,
            `# HELP shield_pending_subscriptions Number of subscriptions pending payment`,
            `# TYPE shield_pending_subscriptions gauge`,
            `shield_pending_subscriptions ${status.stats.pendingSubscriptions}`,
            ``,
            `# HELP shield_total_dca_strategies Total number of DCA strategies`,
            `# TYPE shield_total_dca_strategies gauge`,
            `shield_total_dca_strategies ${status.stats.totalDCAStrategies}`,
            ``,
            `# HELP shield_total_subscriptions Total number of subscriptions`,
            `# TYPE shield_total_subscriptions gauge`,
            `shield_total_subscriptions ${status.stats.totalSubscriptions}`,
          ].join('\n')

          res.writeHead(200, { 'Content-Type': 'text/plain' })
          res.end(metrics)
        } else if (url === '/stats') {
          // Detailed statistics from indexer
          try {
            const [globalStats, recentExecutions, recentPayments] = await Promise.all([
              indexerClient.getGlobalStats(),
              indexerClient.getRecentExecutions(10),
              indexerClient.getRecentPayments(10),
            ])

            res.writeHead(200, { 'Content-Type': 'application/json' })
            res.end(JSON.stringify({
              globalStats,
              recentExecutions,
              recentPayments,
            }, null, 2))
          } catch (error: any) {
            res.writeHead(500, { 'Content-Type': 'application/json' })
            res.end(JSON.stringify({ error: error.message }))
          }
        } else {
          res.writeHead(404, { 'Content-Type': 'application/json' })
          res.end(JSON.stringify({
            error: 'Not Found',
            endpoints: ['/health', '/ready', '/live', '/metrics', '/stats'],
          }))
        }
      } catch (error: any) {
        res.writeHead(500, { 'Content-Type': 'application/json' })
        res.end(JSON.stringify({ error: error.message }))
      }
    })

    this.server.listen(this.port, () => {
      console.log(`[Monitor] Health check server running on http://localhost:${this.port}`)
      console.log(`[Monitor] Endpoints: /health, /ready, /live, /metrics, /stats`)
    })
  }

  stop(): void {
    if (this.server) {
      this.server.close()
      this.server = null
      console.log('[Monitor] Health check server stopped')
    }
  }
}
