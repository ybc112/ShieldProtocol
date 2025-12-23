'use client'

import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { STOP_LOSS_EXECUTOR_ABI, CONTRACT_ADDRESSES } from '@/lib/contracts'
import type { StopLossStrategy, CreateStopLossParams } from '@/types'

export function useStopLossStrategies() {
  const { address } = useAccount()

  const { data: strategyIds, isLoading, error, refetch } = useReadContract({
    address: CONTRACT_ADDRESSES.stopLossExecutor,
    abi: STOP_LOSS_EXECUTOR_ABI,
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

export function useStopLossStrategy(strategyId: `0x${string}` | undefined) {
  const { data, isLoading, error, refetch } = useReadContract({
    address: CONTRACT_ADDRESSES.stopLossExecutor,
    abi: STOP_LOSS_EXECUTOR_ABI,
    functionName: 'getStrategy',
    args: strategyId ? [strategyId] : undefined,
    query: {
      enabled: !!strategyId,
    },
  })

  return {
    strategy: data as StopLossStrategy | undefined,
    isLoading,
    error,
    refetch,
  }
}

export function useShouldTrigger(strategyId: `0x${string}` | undefined) {
  const { data, isLoading, error, refetch } = useReadContract({
    address: CONTRACT_ADDRESSES.stopLossExecutor,
    abi: STOP_LOSS_EXECUTOR_ABI,
    functionName: 'shouldTrigger',
    args: strategyId ? [strategyId] : undefined,
    query: {
      enabled: !!strategyId,
    },
  })

  const result = data as [boolean, bigint] | undefined

  return {
    shouldTrigger: result?.[0],
    currentPrice: result?.[1],
    isLoading,
    error,
    refetch,
  }
}

export function useCurrentTriggerPrice(strategyId: `0x${string}` | undefined) {
  const { data, isLoading, error, refetch } = useReadContract({
    address: CONTRACT_ADDRESSES.stopLossExecutor,
    abi: STOP_LOSS_EXECUTOR_ABI,
    functionName: 'getCurrentTriggerPrice',
    args: strategyId ? [strategyId] : undefined,
    query: {
      enabled: !!strategyId,
    },
  })

  return {
    triggerPrice: data as bigint | undefined,
    isLoading,
    error,
    refetch,
  }
}

export function useCreateStopLossStrategy() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const createStrategy = async (params: CreateStopLossParams) => {
    writeContract({
      address: CONTRACT_ADDRESSES.stopLossExecutor,
      abi: STOP_LOSS_EXECUTOR_ABI,
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

export function useStopLossActions() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const checkAndExecute = async (strategyId: `0x${string}`) => {
    writeContract({
      address: CONTRACT_ADDRESSES.stopLossExecutor,
      abi: STOP_LOSS_EXECUTOR_ABI,
      functionName: 'checkAndExecute',
      args: [strategyId],
    })
  }

  const pauseStrategy = async (strategyId: `0x${string}`) => {
    writeContract({
      address: CONTRACT_ADDRESSES.stopLossExecutor,
      abi: STOP_LOSS_EXECUTOR_ABI,
      functionName: 'pauseStrategy',
      args: [strategyId],
    })
  }

  const resumeStrategy = async (strategyId: `0x${string}`) => {
    writeContract({
      address: CONTRACT_ADDRESSES.stopLossExecutor,
      abi: STOP_LOSS_EXECUTOR_ABI,
      functionName: 'resumeStrategy',
      args: [strategyId],
    })
  }

  const cancelStrategy = async (strategyId: `0x${string}`) => {
    writeContract({
      address: CONTRACT_ADDRESSES.stopLossExecutor,
      abi: STOP_LOSS_EXECUTOR_ABI,
      functionName: 'cancelStrategy',
      args: [strategyId],
    })
  }

  const updateStrategy = async (
    strategyId: `0x${string}`,
    newTriggerValue: bigint,
    newMinAmountOut: bigint
  ) => {
    writeContract({
      address: CONTRACT_ADDRESSES.stopLossExecutor,
      abi: STOP_LOSS_EXECUTOR_ABI,
      functionName: 'updateStrategy',
      args: [strategyId, newTriggerValue, newMinAmountOut],
    })
  }

  return {
    checkAndExecute,
    pauseStrategy,
    resumeStrategy,
    cancelStrategy,
    updateStrategy,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  }
}
