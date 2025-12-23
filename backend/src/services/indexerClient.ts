import { config } from '../config/index.js'

// GraphQL query types
interface DCAStrategy {
  id: string
  userId: string
  sourceTokenId: string
  targetTokenId: string
  amountPerExecution: string
  minAmountOut: string
  intervalSeconds: string
  totalExecutions: number
  executionsCompleted: number
  status: string
  nextExecutionTime: string | null
  lastExecutionTime: string | null
  totalAmountIn: string
  totalAmountOut: string
  createdAt: string
  updatedAt: string
}

interface Subscription {
  id: string
  subscriberId: string
  recipientId: string
  tokenId: string
  amount: string
  billingPeriod: string
  maxPayments: number
  paymentsCompleted: number
  nextPaymentTime: string
  status: string
  totalPaid: string
  createdAt: string
}

interface User {
  id: string
  address: string
  totalInvested: string
  totalReceived: string
  totalDCAExecutions: number
  totalPaymentsMade: number
  totalPaymentsReceived: number
}

interface GlobalStats {
  id: string
  totalUsers: number
  totalShieldsActivated: number
  totalDCAStrategies: number
  totalDCAExecutions: number
  totalDCAVolume: string
  totalSubscriptions: number
  totalPayments: number
  totalPaymentVolume: string
}

interface GraphQLResponse<T> {
  data: T
  errors?: Array<{ message: string }>
}

export class IndexerClient {
  private graphqlUrl: string

  constructor() {
    this.graphqlUrl = config.indexerGraphqlUrl
    console.log(`[Indexer] Client initialized with URL: ${this.graphqlUrl}`)
  }

  private async query<T>(query: string, variables?: Record<string, any>): Promise<T> {
    const response = await fetch(this.graphqlUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ query, variables }),
    })

    if (!response.ok) {
      throw new Error(`GraphQL request failed: ${response.statusText}`)
    }

    const result = await response.json() as GraphQLResponse<T>

    if (result.errors && result.errors.length > 0) {
      throw new Error(`GraphQL errors: ${result.errors.map(e => e.message).join(', ')}`)
    }

    return result.data
  }

  /**
   * Get all active DCA strategies that are ready for execution
   */
  async getActiveStrategies(): Promise<DCAStrategy[]> {
    const now = Math.floor(Date.now() / 1000).toString()

    const data = await this.query<{ dcaStrategys: { items: DCAStrategy[] } }>(`
      query GetActiveStrategies($now: BigInt!) {
        dcaStrategys(
          where: {
            status: "Active",
            nextExecutionTime_lte: $now
          }
          limit: 100
          orderBy: "nextExecutionTime"
          orderDirection: "asc"
        ) {
          items {
            id
            userId
            sourceTokenId
            targetTokenId
            amountPerExecution
            minAmountOut
            intervalSeconds
            totalExecutions
            executionsCompleted
            status
            nextExecutionTime
            lastExecutionTime
            totalAmountIn
            totalAmountOut
            createdAt
            updatedAt
          }
        }
      }
    `, { now })

    return data.dcaStrategys?.items || []
  }

  /**
   * Get all DCA strategies for a specific user
   */
  async getUserStrategies(userId: string): Promise<DCAStrategy[]> {
    const data = await this.query<{ dcaStrategys: { items: DCAStrategy[] } }>(`
      query GetUserStrategies($userId: String!) {
        dcaStrategys(
          where: { userId: $userId }
          limit: 50
          orderBy: "createdAt"
          orderDirection: "desc"
        ) {
          items {
            id
            userId
            sourceTokenId
            targetTokenId
            amountPerExecution
            minAmountOut
            intervalSeconds
            totalExecutions
            executionsCompleted
            status
            nextExecutionTime
            lastExecutionTime
            totalAmountIn
            totalAmountOut
            createdAt
            updatedAt
          }
        }
      }
    `, { userId: userId.toLowerCase() })

    return data.dcaStrategys?.items || []
  }

  /**
   * Get active subscriptions that are due for payment
   */
  async getDueSubscriptions(): Promise<Subscription[]> {
    const now = Math.floor(Date.now() / 1000).toString()

    const data = await this.query<{ subscriptions: { items: Subscription[] } }>(`
      query GetDueSubscriptions($now: BigInt!) {
        subscriptions(
          where: {
            status: "Active",
            nextPaymentTime_lte: $now
          }
          limit: 100
          orderBy: "nextPaymentTime"
          orderDirection: "asc"
        ) {
          items {
            id
            subscriberId
            recipientId
            tokenId
            amount
            billingPeriod
            maxPayments
            paymentsCompleted
            nextPaymentTime
            status
            totalPaid
            createdAt
          }
        }
      }
    `, { now })

    return data.subscriptions?.items || []
  }

  /**
   * Get all active subscriptions
   */
  async getActiveSubscriptions(): Promise<Subscription[]> {
    const data = await this.query<{ subscriptions: { items: Subscription[] } }>(`
      query GetActiveSubscriptions {
        subscriptions(
          where: { status: "Active" }
          limit: 100
          orderBy: "nextPaymentTime"
          orderDirection: "asc"
        ) {
          items {
            id
            subscriberId
            recipientId
            tokenId
            amount
            billingPeriod
            maxPayments
            paymentsCompleted
            nextPaymentTime
            status
            totalPaid
            createdAt
          }
        }
      }
    `)

    return data.subscriptions?.items || []
  }

  /**
   * Get user by address
   */
  async getUser(address: string): Promise<User | null> {
    const data = await this.query<{ user: User | null }>(`
      query GetUser($id: String!) {
        user(id: $id) {
          id
          address
          totalInvested
          totalReceived
          totalDCAExecutions
          totalPaymentsMade
          totalPaymentsReceived
        }
      }
    `, { id: address.toLowerCase() })

    return data.user
  }

  /**
   * Get global statistics
   */
  async getGlobalStats(): Promise<GlobalStats | null> {
    const data = await this.query<{ globalStats: GlobalStats | null }>(`
      query GetGlobalStats {
        globalStats(id: "global") {
          id
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
    `)

    return data.globalStats
  }

  /**
   * Check if indexer is healthy
   */
  async isHealthy(): Promise<boolean> {
    try {
      const response = await fetch(config.indexerUrl, { method: 'GET' })
      return response.ok
    } catch {
      return false
    }
  }

  /**
   * Get recent DCA executions
   */
  async getRecentExecutions(limit: number = 10): Promise<any[]> {
    const data = await this.query<{ dcaExecutions: { items: any[] } }>(`
      query GetRecentExecutions($limit: Int!) {
        dcaExecutions(
          limit: $limit
          orderBy: "timestamp"
          orderDirection: "desc"
        ) {
          items {
            id
            strategyId
            amountIn
            amountOut
            price
            executionNumber
            txHash
            blockNumber
            timestamp
          }
        }
      }
    `, { limit })

    return data.dcaExecutions?.items || []
  }

  /**
   * Get recent payments
   */
  async getRecentPayments(limit: number = 10): Promise<any[]> {
    const data = await this.query<{ payments: { items: any[] } }>(`
      query GetRecentPayments($limit: Int!) {
        payments(
          limit: $limit
          orderBy: "timestamp"
          orderDirection: "desc"
        ) {
          items {
            id
            subscriptionId
            amount
            paymentNumber
            txHash
            blockNumber
            timestamp
          }
        }
      }
    `, { limit })

    return data.payments?.items || []
  }
}

// Singleton instance
export const indexerClient = new IndexerClient()
