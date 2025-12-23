'use client'

import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { REBALANCE_EXECUTOR_ABI, CONTRACT_ADDRESSES } from '@/lib/contracts'
import type { RebalanceStrategy, CreateRebalanceParams } from '@/types'

export function useRebalanceStrategies() {
  const { address } = useAccount()

  const { data: strategyIds, isLoading, error, refetch } = useReadContract({
    address: CONTRACT_ADDRESSES.rebalanceExecutor,
    abi: REBALANCE_EXECUTOR_ABI,
    functionName: 'getUserStrategies',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
    },
  })

  return {
    strategyIds: strategyIds as `0x${string}`[] | undefined,
    isLoading,
    error,
    refetch,
  }
}

export function useRebalanceStrategy(strategyId: `0x${string}` | undefined) {
  const { data, isLoading, error, refetch } = useReadContract({
    address: CONTRACT_ADDRESSES.rebalanceExecutor,
    abi: REBALANCE_EXECUTOR_ABI,
    functionName: 'getStrategy',
    args: strategyId ? [strategyId] : undefined,
    query: {
      enabled: !!strategyId,
    },
  })

  return {
    strategy: data as RebalanceStrategy | undefined,
    isLoading,
    error,
    refetch,
  }
}

export function useNeedsRebalance(strategyId: `0x${string}` | undefined) {
  const { data, isLoading, error, refetch } = useReadContract({
    address: CONTRACT_ADDRESSES.rebalanceExecutor,
    abi: REBALANCE_EXECUTOR_ABI,
    functionName: 'needsRebalance',
    args: strategyId ? [strategyId] : undefined,
    query: {
      enabled: !!strategyId,
    },
  })

  const result = data as [boolean, string] | undefined

  return {
    needsRebalance: result?.[0],
    reason: result?.[1],
    isLoading,
    error,
    refetch,
  }
}

export function usePortfolioValue(strategyId: `0x${string}` | undefined) {
  const { data, isLoading, error, refetch } = useReadContract({
    address: CONTRACT_ADDRESSES.rebalanceExecutor,
    abi: REBALANCE_EXECUTOR_ABI,
    functionName: 'getPortfolioValue',
    args: strategyId ? [strategyId] : undefined,
    query: {
      enabled: !!strategyId,
    },
  })

  return {
    portfolioValue: data as bigint | undefined,
    isLoading,
    error,
    refetch,
  }
}

export function useCreateRebalanceStrategy() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const createStrategy = async (params: CreateRebalanceParams) => {
    writeContract({
      address: CONTRACT_ADDRESSES.rebalanceExecutor,
      abi: REBALANCE_EXECUTOR_ABI,
      functionName: 'createStrategy',
      args: [params],
    })
  }

  return {
    createStrategy,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  }
}

export function useRebalanceActions() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const executeRebalance = async (strategyId: `0x${string}`) => {
    writeContract({
      address: CONTRACT_ADDRESSES.rebalanceExecutor,
      abi: REBALANCE_EXECUTOR_ABI,
      functionName: 'executeRebalance',
      args: [strategyId],
    })
  }

  const pauseStrategy = async (strategyId: `0x${string}`) => {
    writeContract({
      address: CONTRACT_ADDRESSES.rebalanceExecutor,
      abi: REBALANCE_EXECUTOR_ABI,
      functionName: 'pauseStrategy',
      args: [strategyId],
    })
  }

  const resumeStrategy = async (strategyId: `0x${string}`) => {
    writeContract({
      address: CONTRACT_ADDRESSES.rebalanceExecutor,
      abi: REBALANCE_EXECUTOR_ABI,
      functionName: 'resumeStrategy',
      args: [strategyId],
    })
  }

  const cancelStrategy = async (strategyId: `0x${string}`) => {
    writeContract({
      address: CONTRACT_ADDRESSES.rebalanceExecutor,
      abi: REBALANCE_EXECUTOR_ABI,
      functionName: 'cancelStrategy',
      args: [strategyId],
    })
  }

  return {
    executeRebalance,
    pauseStrategy,
    resumeStrategy,
    cancelStrategy,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  }
}
