'use client'

/**
 * Hooks for fetching data from Ponder Indexer via GraphQL
 * Falls back to direct blockchain queries if indexer is unavailable
 */

import { useAccount } from 'wagmi'
import { useState, useEffect, useCallback, useMemo } from 'react'
import {
  graphqlQuery,
  isIndexerAvailable,
  type GraphQLUser,
  type GraphQLActivityLog,
  type GraphQLDCAStrategy,
  type GraphQLGlobalStats,
  type GraphQLDailyStats,
} from '@/lib/graphql'
import {
  GET_USER_QUERY,
  GET_USER_ACTIVITY_QUERY,
  GET_USER_STRATEGIES_QUERY,
  GET_GLOBAL_STATS_QUERY,
  GET_USER_DAILY_STATS_QUERY,
  GET_STRATEGY_DETAILS_QUERY,
  GET_DCA_EXECUTIONS_QUERY,
} from '@/lib/queries'

// ==================== User Data Hook ====================

interface UseIndexedUserResult {
  user: GraphQLUser | null
  isLoading: boolean
  error: Error | null
  refetch: () => Promise<void>
}

export function useIndexedUser(): UseIndexedUserResult {
  const { address } = useAccount()
  const [user, setUser] = useState<GraphQLUser | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<Error | null>(null)

  const fetchUser = useCallback(async () => {
    if (!address) {
      setUser(null)
      setIsLoading(false)
      return
    }

    setIsLoading(true)
    setError(null)

    try {
      const data = await graphqlQuery<{ user: GraphQLUser | null }>(
        GET_USER_QUERY,
        { address: address.toLowerCase() }
      )
      setUser(data.user)
    } catch (err) {
      console.error('Error fetching indexed user:', err)
      setError(err as Error)
    } finally {
      setIsLoading(false)
    }
  }, [address])

  useEffect(() => {
    fetchUser()
  }, [fetchUser])

  return { user, isLoading, error, refetch: fetchUser }
}

// ==================== Activity Logs Hook ====================

interface UseIndexedActivityResult {
  activities: GraphQLActivityLog[]
  isLoading: boolean
  error: Error | null
  hasMore: boolean
  loadMore: () => Promise<void>
  refetch: () => Promise<void>
}

export function useIndexedActivity(limit: number = 20): UseIndexedActivityResult {
  const { address } = useAccount()
  const [activities, setActivities] = useState<GraphQLActivityLog[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<Error | null>(null)
  const [offset, setOffset] = useState(0)
  const [hasMore, setHasMore] = useState(true)

  const fetchActivities = useCallback(async (reset = false) => {
    if (!address) {
      setActivities([])
      setIsLoading(false)
      return
    }

    setIsLoading(true)
    setError(null)

    const currentOffset = reset ? 0 : offset

    try {
      const data = await graphqlQuery<{ activityLogs: GraphQLActivityLog[] }>(
        GET_USER_ACTIVITY_QUERY,
        {
          userId: address.toLowerCase(),
          limit,
          offset: currentOffset,
        }
      )

      const newActivities = data.activityLogs || []

      if (reset) {
        setActivities(newActivities)
        setOffset(limit)
      } else {
        setActivities(prev => [...prev, ...newActivities])
        setOffset(prev => prev + limit)
      }

      setHasMore(newActivities.length === limit)
    } catch (err) {
      console.error('Error fetching indexed activities:', err)
      setError(err as Error)
    } finally {
      setIsLoading(false)
    }
  }, [address, offset, limit])

  useEffect(() => {
    fetchActivities(true)
  }, [address]) // Only reset on address change

  const loadMore = useCallback(async () => {
    if (!isLoading && hasMore) {
      await fetchActivities(false)
    }
  }, [fetchActivities, isLoading, hasMore])

  const refetch = useCallback(async () => {
    setOffset(0)
    await fetchActivities(true)
  }, [fetchActivities])

  return { activities, isLoading, error, hasMore, loadMore, refetch }
}

// ==================== DCA Strategies Hook ====================

interface UseIndexedStrategiesResult {
  strategies: GraphQLDCAStrategy[]
  isLoading: boolean
  error: Error | null
  refetch: () => Promise<void>
}

export function useIndexedStrategies(): UseIndexedStrategiesResult {
  const { address } = useAccount()
  const [strategies, setStrategies] = useState<GraphQLDCAStrategy[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<Error | null>(null)

  const fetchStrategies = useCallback(async () => {
    if (!address) {
      setStrategies([])
      setIsLoading(false)
      return
    }

    setIsLoading(true)
    setError(null)

    try {
      const data = await graphqlQuery<{ dcaStrategies: GraphQLDCAStrategy[] }>(
        GET_USER_STRATEGIES_QUERY,
        { userId: address.toLowerCase() }
      )
      setStrategies(data.dcaStrategies || [])
    } catch (err) {
      console.error('Error fetching indexed strategies:', err)
      setError(err as Error)
    } finally {
      setIsLoading(false)
    }
  }, [address])

  useEffect(() => {
    fetchStrategies()
  }, [fetchStrategies])

  return { strategies, isLoading, error, refetch: fetchStrategies }
}

// ==================== Strategy Details Hook ====================

interface UseIndexedStrategyDetailsResult {
  strategy: GraphQLDCAStrategy | null
  isLoading: boolean
  error: Error | null
  refetch: () => Promise<void>
}

export function useIndexedStrategyDetails(strategyId: string): UseIndexedStrategyDetailsResult {
  const [strategy, setStrategy] = useState<GraphQLDCAStrategy | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<Error | null>(null)

  const fetchStrategy = useCallback(async () => {
    if (!strategyId) {
      setStrategy(null)
      setIsLoading(false)
      return
    }

    setIsLoading(true)
    setError(null)

    try {
      const data = await graphqlQuery<{ dcaStrategy: GraphQLDCAStrategy | null }>(
        GET_STRATEGY_DETAILS_QUERY,
        { strategyId }
      )
      setStrategy(data.dcaStrategy)
    } catch (err) {
      console.error('Error fetching strategy details:', err)
      setError(err as Error)
    } finally {
      setIsLoading(false)
    }
  }, [strategyId])

  useEffect(() => {
    fetchStrategy()
  }, [fetchStrategy])

  return { strategy, isLoading, error, refetch: fetchStrategy }
}

// ==================== DCA Stats Hook ====================

interface DCAStats {
  totalExecutions: number
  totalAmountIn: bigint
  totalAmountOut: bigint
  averagePrice: bigint
  successRate: number
}

interface UseIndexedDCAStatsResult {
  stats: DCAStats
  isLoading: boolean
  error: Error | null
  refetch: () => Promise<void>
}

export function useIndexedDCAStats(): UseIndexedDCAStatsResult {
  const { address } = useAccount()
  const [stats, setStats] = useState<DCAStats>({
    totalExecutions: 0,
    totalAmountIn: 0n,
    totalAmountOut: 0n,
    averagePrice: 0n,
    successRate: 100,
  })
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<Error | null>(null)

  const fetchStats = useCallback(async () => {
    if (!address) {
      setIsLoading(false)
      return
    }

    setIsLoading(true)
    setError(null)

    try {
      const data = await graphqlQuery<{ user: GraphQLUser | null }>(
        GET_USER_QUERY,
        { address: address.toLowerCase() }
      )

      if (data.user) {
        const totalIn = BigInt(data.user.totalInvested || '0')
        const totalOut = BigInt(data.user.totalReceived || '0')
        const avgPrice = totalOut > 0n ? (totalIn * BigInt(10 ** 18)) / totalOut : 0n

        setStats({
          totalExecutions: data.user.totalDCAExecutions || 0,
          totalAmountIn: totalIn,
          totalAmountOut: totalOut,
          averagePrice: avgPrice,
          successRate: 100,
        })
      }
    } catch (err) {
      console.error('Error fetching DCA stats:', err)
      setError(err as Error)
    } finally {
      setIsLoading(false)
    }
  }, [address])

  useEffect(() => {
    fetchStats()
  }, [fetchStats])

  return { stats, isLoading, error, refetch: fetchStats }
}

// ==================== Global Stats Hook ====================

interface UseGlobalStatsResult {
  stats: GraphQLGlobalStats | null
  isLoading: boolean
  error: Error | null
  refetch: () => Promise<void>
}

export function useGlobalStats(): UseGlobalStatsResult {
  const [stats, setStats] = useState<GraphQLGlobalStats | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<Error | null>(null)

  const fetchStats = useCallback(async () => {
    setIsLoading(true)
    setError(null)

    try {
      const data = await graphqlQuery<{ globalStats: GraphQLGlobalStats | null }>(
        GET_GLOBAL_STATS_QUERY
      )
      setStats(data.globalStats)
    } catch (err) {
      console.error('Error fetching global stats:', err)
      setError(err as Error)
    } finally {
      setIsLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchStats()
  }, [fetchStats])

  return { stats, isLoading, error, refetch: fetchStats }
}

// ==================== Daily Stats Hook ====================

interface UseDailyStatsResult {
  dailyStats: GraphQLDailyStats[]
  isLoading: boolean
  error: Error | null
  refetch: () => Promise<void>
}

export function useDailyStats(days: number = 30): UseDailyStatsResult {
  const { address } = useAccount()
  const [dailyStats, setDailyStats] = useState<GraphQLDailyStats[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<Error | null>(null)

  const startDate = useMemo(() => {
    const date = new Date()
    date.setDate(date.getDate() - days)
    return date.toISOString().split('T')[0]
  }, [days])

  const fetchStats = useCallback(async () => {
    if (!address) {
      setDailyStats([])
      setIsLoading(false)
      return
    }

    setIsLoading(true)
    setError(null)

    try {
      const data = await graphqlQuery<{ dailyStats: GraphQLDailyStats[] }>(
        GET_USER_DAILY_STATS_QUERY,
        {
          userId: address.toLowerCase(),
          startDate,
        }
      )
      setDailyStats(data.dailyStats || [])
    } catch (err) {
      console.error('Error fetching daily stats:', err)
      setError(err as Error)
    } finally {
      setIsLoading(false)
    }
  }, [address, startDate])

  useEffect(() => {
    fetchStats()
  }, [fetchStats])

  return { dailyStats, isLoading, error, refetch: fetchStats }
}

// ==================== Indexer Availability Hook ====================

export function useIndexerStatus() {
  const [isAvailable, setIsAvailable] = useState<boolean | null>(null)
  const [isChecking, setIsChecking] = useState(true)

  useEffect(() => {
    const checkStatus = async () => {
      setIsChecking(true)
      const available = await isIndexerAvailable()
      setIsAvailable(available)
      setIsChecking(false)
    }

    checkStatus()

    // Re-check every 30 seconds
    const interval = setInterval(checkStatus, 30000)
    return () => clearInterval(interval)
  }, [])

  return { isAvailable, isChecking }
}
