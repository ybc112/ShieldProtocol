'use client'

import { useAccount, usePublicClient } from 'wagmi'
import { useState, useEffect, useCallback } from 'react'
import { parseAbiItem, type Log } from 'viem'
import { CONTRACT_ADDRESSES } from '@/lib/contracts'

// Event signatures
const SHIELD_EVENTS = {
  ShieldActivated: parseAbiItem('event ShieldActivated(address indexed user, uint256 dailyLimit, uint256 singleTxLimit, uint256 timestamp)'),
  ShieldDeactivated: parseAbiItem('event ShieldDeactivated(address indexed user, uint256 timestamp)'),
  EmergencyModeEnabled: parseAbiItem('event EmergencyModeEnabled(address indexed user, uint256 timestamp)'),
  EmergencyModeDisabled: parseAbiItem('event EmergencyModeDisabled(address indexed user, uint256 timestamp)'),
}

const DCA_EVENTS = {
  StrategyCreated: parseAbiItem('event StrategyCreated(bytes32 indexed strategyId, address indexed user, address sourceToken, address targetToken, uint256 amountPerExecution, uint256 intervalSeconds, uint256 totalExecutions)'),
  DCAExecuted: parseAbiItem('event DCAExecuted(bytes32 indexed strategyId, address indexed user, uint256 amountIn, uint256 amountOut, uint256 executionsCompleted, uint256 timestamp)'),
  StrategyPaused: parseAbiItem('event StrategyPaused(bytes32 indexed strategyId, uint256 timestamp)'),
  StrategyResumed: parseAbiItem('event StrategyResumed(bytes32 indexed strategyId, uint256 timestamp)'),
  StrategyCancelled: parseAbiItem('event StrategyCancelled(bytes32 indexed strategyId, uint256 timestamp)'),
}

const SUBSCRIPTION_EVENTS = {
  SubscriptionCreated: parseAbiItem('event SubscriptionCreated(bytes32 indexed subscriptionId, address indexed subscriber, address indexed recipient, address token, uint256 amount, uint8 billingPeriod)'),
  PaymentExecuted: parseAbiItem('event PaymentExecuted(bytes32 indexed subscriptionId, address indexed subscriber, address indexed recipient, uint256 amount, uint256 paymentNumber, uint256 timestamp)'),
  SubscriptionCancelled: parseAbiItem('event SubscriptionCancelled(bytes32 indexed subscriptionId, address indexed subscriber, uint256 timestamp)'),
}

export type ActivityType =
  | 'shield_activated'
  | 'shield_deactivated'
  | 'emergency_enabled'
  | 'emergency_disabled'
  | 'strategy_created'
  | 'strategy_executed'
  | 'strategy_paused'
  | 'strategy_resumed'
  | 'strategy_cancelled'
  | 'subscription_created'
  | 'payment_executed'
  | 'subscription_cancelled'

export interface Activity {
  id: string
  type: ActivityType
  timestamp: number
  txHash: string
  blockNumber: bigint
  details: Record<string, string | number | bigint>
}

export function useActivityLogs() {
  const { address } = useAccount()
  const publicClient = usePublicClient()
  const [activities, setActivities] = useState<Activity[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<Error | null>(null)

  const fetchLogs = useCallback(async () => {
    if (!address || !publicClient) {
      setActivities([])
      setIsLoading(false)
      return
    }

    setIsLoading(true)
    setError(null)

    try {
      const currentBlock = await publicClient.getBlockNumber()
      // Look back ~7 days worth of blocks (assuming ~12 second blocks)
      const fromBlock = currentBlock - BigInt(50000)

      const allActivities: Activity[] = []

      // Fetch Shield events
      try {
        const shieldActivatedLogs = await publicClient.getLogs({
          address: CONTRACT_ADDRESSES.shieldCore,
          event: SHIELD_EVENTS.ShieldActivated,
          args: { user: address },
          fromBlock: fromBlock > 0n ? fromBlock : 0n,
          toBlock: 'latest',
        })

        shieldActivatedLogs.forEach((log) => {
          allActivities.push({
            id: `${log.transactionHash}-${log.logIndex}`,
            type: 'shield_activated',
            timestamp: Number(log.args.timestamp || 0) * 1000,
            txHash: log.transactionHash,
            blockNumber: log.blockNumber,
            details: {
              dailyLimit: log.args.dailyLimit?.toString() || '0',
              singleTxLimit: log.args.singleTxLimit?.toString() || '0',
            },
          })
        })

        const emergencyEnabledLogs = await publicClient.getLogs({
          address: CONTRACT_ADDRESSES.shieldCore,
          event: SHIELD_EVENTS.EmergencyModeEnabled,
          args: { user: address },
          fromBlock: fromBlock > 0n ? fromBlock : 0n,
          toBlock: 'latest',
        })

        emergencyEnabledLogs.forEach((log) => {
          allActivities.push({
            id: `${log.transactionHash}-${log.logIndex}`,
            type: 'emergency_enabled',
            timestamp: Number(log.args.timestamp || 0) * 1000,
            txHash: log.transactionHash,
            blockNumber: log.blockNumber,
            details: {},
          })
        })

        const emergencyDisabledLogs = await publicClient.getLogs({
          address: CONTRACT_ADDRESSES.shieldCore,
          event: SHIELD_EVENTS.EmergencyModeDisabled,
          args: { user: address },
          fromBlock: fromBlock > 0n ? fromBlock : 0n,
          toBlock: 'latest',
        })

        emergencyDisabledLogs.forEach((log) => {
          allActivities.push({
            id: `${log.transactionHash}-${log.logIndex}`,
            type: 'emergency_disabled',
            timestamp: Number(log.args.timestamp || 0) * 1000,
            txHash: log.transactionHash,
            blockNumber: log.blockNumber,
            details: {},
          })
        })
      } catch (e) {
        console.warn('Error fetching shield events:', e)
      }

      // Fetch DCA events
      try {
        const strategyCreatedLogs = await publicClient.getLogs({
          address: CONTRACT_ADDRESSES.dcaExecutor,
          event: DCA_EVENTS.StrategyCreated,
          args: { user: address },
          fromBlock: fromBlock > 0n ? fromBlock : 0n,
          toBlock: 'latest',
        })

        strategyCreatedLogs.forEach((log) => {
          allActivities.push({
            id: `${log.transactionHash}-${log.logIndex}`,
            type: 'strategy_created',
            timestamp: Date.now(), // Will be replaced with block timestamp
            txHash: log.transactionHash,
            blockNumber: log.blockNumber,
            details: {
              strategyId: log.args.strategyId || '',
              sourceToken: log.args.sourceToken || '',
              targetToken: log.args.targetToken || '',
              amountPerExecution: log.args.amountPerExecution?.toString() || '0',
              totalExecutions: log.args.totalExecutions?.toString() || '0',
            },
          })
        })

        const dcaExecutedLogs = await publicClient.getLogs({
          address: CONTRACT_ADDRESSES.dcaExecutor,
          event: DCA_EVENTS.DCAExecuted,
          args: { user: address },
          fromBlock: fromBlock > 0n ? fromBlock : 0n,
          toBlock: 'latest',
        })

        dcaExecutedLogs.forEach((log) => {
          allActivities.push({
            id: `${log.transactionHash}-${log.logIndex}`,
            type: 'strategy_executed',
            timestamp: Number(log.args.timestamp || 0) * 1000,
            txHash: log.transactionHash,
            blockNumber: log.blockNumber,
            details: {
              strategyId: log.args.strategyId || '',
              amountIn: log.args.amountIn?.toString() || '0',
              amountOut: log.args.amountOut?.toString() || '0',
              executionsCompleted: log.args.executionsCompleted?.toString() || '0',
            },
          })
        })
      } catch (e) {
        console.warn('Error fetching DCA events:', e)
      }

      // Fetch Subscription events
      try {
        const subscriptionCreatedLogs = await publicClient.getLogs({
          address: CONTRACT_ADDRESSES.subscriptionManager,
          event: SUBSCRIPTION_EVENTS.SubscriptionCreated,
          args: { subscriber: address },
          fromBlock: fromBlock > 0n ? fromBlock : 0n,
          toBlock: 'latest',
        })

        subscriptionCreatedLogs.forEach((log) => {
          allActivities.push({
            id: `${log.transactionHash}-${log.logIndex}`,
            type: 'subscription_created',
            timestamp: Date.now(),
            txHash: log.transactionHash,
            blockNumber: log.blockNumber,
            details: {
              subscriptionId: log.args.subscriptionId || '',
              recipient: log.args.recipient || '',
              amount: log.args.amount?.toString() || '0',
            },
          })
        })

        const paymentExecutedLogs = await publicClient.getLogs({
          address: CONTRACT_ADDRESSES.subscriptionManager,
          event: SUBSCRIPTION_EVENTS.PaymentExecuted,
          args: { subscriber: address },
          fromBlock: fromBlock > 0n ? fromBlock : 0n,
          toBlock: 'latest',
        })

        paymentExecutedLogs.forEach((log) => {
          allActivities.push({
            id: `${log.transactionHash}-${log.logIndex}`,
            type: 'payment_executed',
            timestamp: Number(log.args.timestamp || 0) * 1000,
            txHash: log.transactionHash,
            blockNumber: log.blockNumber,
            details: {
              subscriptionId: log.args.subscriptionId || '',
              amount: log.args.amount?.toString() || '0',
              paymentNumber: log.args.paymentNumber?.toString() || '0',
            },
          })
        })
      } catch (e) {
        console.warn('Error fetching subscription events:', e)
      }

      // Sort by block number (newest first)
      allActivities.sort((a, b) => Number(b.blockNumber - a.blockNumber))

      setActivities(allActivities)
    } catch (err) {
      console.error('Error fetching activity logs:', err)
      setError(err as Error)
    } finally {
      setIsLoading(false)
    }
  }, [address, publicClient])

  useEffect(() => {
    fetchLogs()
  }, [fetchLogs])

  return {
    activities,
    isLoading,
    error,
    refetch: fetchLogs,
  }
}

// Hook for DCA execution statistics
export function useDCAStats() {
  const { address } = useAccount()
  const publicClient = usePublicClient()
  const [stats, setStats] = useState({
    totalExecutions: 0,
    totalAmountIn: 0n,
    totalAmountOut: 0n,
    successRate: 100,
  })
  const [isLoading, setIsLoading] = useState(true)

  const fetchStats = useCallback(async () => {
    if (!address || !publicClient) {
      setIsLoading(false)
      return
    }

    setIsLoading(true)

    try {
      const currentBlock = await publicClient.getBlockNumber()
      const fromBlock = currentBlock - BigInt(100000) // Look back further for stats

      const dcaExecutedLogs = await publicClient.getLogs({
        address: CONTRACT_ADDRESSES.dcaExecutor,
        event: DCA_EVENTS.DCAExecuted,
        args: { user: address },
        fromBlock: fromBlock > 0n ? fromBlock : 0n,
        toBlock: 'latest',
      })

      let totalIn = 0n
      let totalOut = 0n

      dcaExecutedLogs.forEach((log) => {
        totalIn += log.args.amountIn || 0n
        totalOut += log.args.amountOut || 0n
      })

      setStats({
        totalExecutions: dcaExecutedLogs.length,
        totalAmountIn: totalIn,
        totalAmountOut: totalOut,
        successRate: 100, // All logged events are successful
      })
    } catch (err) {
      console.error('Error fetching DCA stats:', err)
    } finally {
      setIsLoading(false)
    }
  }, [address, publicClient])

  useEffect(() => {
    fetchStats()
  }, [fetchStats])

  return {
    stats,
    isLoading,
    refetch: fetchStats,
  }
}
