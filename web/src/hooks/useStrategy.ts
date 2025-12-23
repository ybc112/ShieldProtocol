'use client'

import { useAccount, useReadContract, useReadContracts, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { DCA_EXECUTOR_ABI, CONTRACT_ADDRESSES } from '@/lib/contracts'
import type { DCAStrategy, StrategyStats, CreateStrategyParams, StrategyStatus } from '@/types'

export function useUserStrategies() {
  const { address } = useAccount()

  const { data: strategyIds, isLoading: isLoadingIds, refetch } = useReadContract({
    address: CONTRACT_ADDRESSES.dcaExecutor,
    abi: DCA_EXECUTOR_ABI,
    functionName: 'getUserStrategies',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
    },
  })

  return {
    strategyIds: strategyIds as `0x${string}`[] | undefined,
    isLoading: isLoadingIds,
    refetch,
  }
}

export function useStrategy(strategyId: `0x${string}` | undefined) {
  const { data, isLoading, error, refetch } = useReadContract({
    address: CONTRACT_ADDRESSES.dcaExecutor,
    abi: DCA_EXECUTOR_ABI,
    functionName: 'getStrategy',
    args: strategyId ? [strategyId] : undefined,
    query: {
      enabled: !!strategyId,
    },
  })

  const strategy: DCAStrategy | null = data ? {
    user: data.user,
    sourceToken: data.sourceToken,
    targetToken: data.targetToken,
    amountPerExecution: data.amountPerExecution,
    minAmountOut: data.minAmountOut,
    intervalSeconds: data.intervalSeconds,
    nextExecutionTime: data.nextExecutionTime,
    totalExecutions: data.totalExecutions,
    executionsCompleted: data.executionsCompleted,
    poolFee: data.poolFee,
    status: data.status as StrategyStatus,
    createdAt: data.createdAt,
    updatedAt: data.updatedAt,
  } : null

  return {
    strategy,
    isLoading,
    error,
    refetch,
  }
}

export function useStrategyStats(strategyId: `0x${string}` | undefined) {
  const { data, isLoading, error } = useReadContract({
    address: CONTRACT_ADDRESSES.dcaExecutor,
    abi: DCA_EXECUTOR_ABI,
    functionName: 'getStrategyStats',
    args: strategyId ? [strategyId] : undefined,
    query: {
      enabled: !!strategyId,
    },
  })

  const stats: StrategyStats | null = data ? {
    totalIn: data[0],
    totalOut: data[1],
    averagePrice: data[2],
    executionsCompleted: data[3],
  } : null

  return {
    stats,
    isLoading,
    error,
  }
}

export function useCreateStrategy() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const createStrategy = async (params: CreateStrategyParams) => {
    writeContract({
      address: CONTRACT_ADDRESSES.dcaExecutor,
      abi: DCA_EXECUTOR_ABI,
      functionName: 'createStrategy',
      args: [{
        sourceToken: params.sourceToken,
        targetToken: params.targetToken,
        amountPerExecution: params.amountPerExecution,
        minAmountOut: params.minAmountOut,
        intervalSeconds: params.intervalSeconds,
        totalExecutions: params.totalExecutions,
        poolFee: params.poolFee,
      }],
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

export function usePauseStrategy() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const pauseStrategy = async (strategyId: `0x${string}`) => {
    writeContract({
      address: CONTRACT_ADDRESSES.dcaExecutor,
      abi: DCA_EXECUTOR_ABI,
      functionName: 'pauseStrategy',
      args: [strategyId],
    })
  }

  return {
    pauseStrategy,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  }
}

export function useResumeStrategy() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const resumeStrategy = async (strategyId: `0x${string}`) => {
    writeContract({
      address: CONTRACT_ADDRESSES.dcaExecutor,
      abi: DCA_EXECUTOR_ABI,
      functionName: 'resumeStrategy',
      args: [strategyId],
    })
  }

  return {
    resumeStrategy,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  }
}

export function useCancelStrategy() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const cancelStrategy = async (strategyId: `0x${string}`) => {
    writeContract({
      address: CONTRACT_ADDRESSES.dcaExecutor,
      abi: DCA_EXECUTOR_ABI,
      functionName: 'cancelStrategy',
      args: [strategyId],
    })
  }

  return {
    cancelStrategy,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  }
}

export function useExecuteDCA() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const executeDCA = async (strategyId: `0x${string}`) => {
    writeContract({
      address: CONTRACT_ADDRESSES.dcaExecutor,
      abi: DCA_EXECUTOR_ABI,
      functionName: 'executeDCA',
      args: [strategyId],
    })
  }

  return {
    executeDCA,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  }
}

export function useCanExecute(strategyId: `0x${string}` | undefined) {
  const { data, isLoading, error, refetch } = useReadContract({
    address: CONTRACT_ADDRESSES.dcaExecutor,
    abi: DCA_EXECUTOR_ABI,
    functionName: 'canExecute',
    args: strategyId ? [strategyId] : undefined,
    query: {
      enabled: !!strategyId,
    },
  })

  return {
    canExecute: data?.[0] ?? false,
    reason: data?.[1] ?? '',
    isLoading,
    error,
    refetch,
  }
}
