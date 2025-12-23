'use client'

import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { SHIELD_CORE_ABI, CONTRACT_ADDRESSES } from '@/lib/contracts'
import { TOKENS } from '@/lib/wagmi'
import type { ShieldConfig } from '@/types'

export function useShieldConfig() {
  const { address } = useAccount()

  const { data, isLoading, error, refetch } = useReadContract({
    address: CONTRACT_ADDRESSES.shieldCore,
    abi: SHIELD_CORE_ABI,
    functionName: 'getShieldConfig',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
    },
  })

  const config: ShieldConfig | null = data ? {
    dailySpendLimit: data.dailySpendLimit,
    singleTxLimit: data.singleTxLimit,
    spentToday: data.spentToday,
    lastResetTimestamp: data.lastResetTimestamp,
    isActive: data.isActive,
    emergencyMode: data.emergencyMode,
  } : null

  return {
    config,
    isLoading,
    error,
    refetch,
  }
}

export function useRemainingAllowance(token?: `0x${string}`) {
  const { address } = useAccount()
  const tokenAddress = token || TOKENS.USDC

  const { data, isLoading, error, refetch } = useReadContract({
    address: CONTRACT_ADDRESSES.shieldCore,
    abi: SHIELD_CORE_ABI,
    functionName: 'getRemainingDailyAllowance',
    args: address ? [address, tokenAddress] : undefined,
    query: {
      enabled: !!address,
    },
  })

  return {
    remainingAllowance: data as bigint | undefined,
    isLoading,
    error,
    refetch,
  }
}

export function useActivateShield() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const activate = async (dailyLimit: bigint, singleTxLimit: bigint) => {
    writeContract({
      address: CONTRACT_ADDRESSES.shieldCore,
      abi: SHIELD_CORE_ABI,
      functionName: 'activateShield',
      args: [dailyLimit, singleTxLimit],
    })
  }

  return {
    activate,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  }
}

export function useDeactivateShield() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const deactivate = async () => {
    writeContract({
      address: CONTRACT_ADDRESSES.shieldCore,
      abi: SHIELD_CORE_ABI,
      functionName: 'deactivateShield',
    })
  }

  return {
    deactivate,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  }
}

export function useEmergencyMode() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const enableEmergency = async () => {
    writeContract({
      address: CONTRACT_ADDRESSES.shieldCore,
      abi: SHIELD_CORE_ABI,
      functionName: 'enableEmergencyMode',
    })
  }

  const disableEmergency = async () => {
    writeContract({
      address: CONTRACT_ADDRESSES.shieldCore,
      abi: SHIELD_CORE_ABI,
      functionName: 'disableEmergencyMode',
    })
  }

  return {
    enableEmergency,
    disableEmergency,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  }
}

export function useUpdateShieldConfig() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const proposeUpdate = async (newDailyLimit: bigint, newSingleTxLimit: bigint) => {
    writeContract({
      address: CONTRACT_ADDRESSES.shieldCore,
      abi: SHIELD_CORE_ABI,
      functionName: 'proposeShieldConfigUpdate',
      args: [newDailyLimit, newSingleTxLimit],
    })
  }

  const executeUpdate = async () => {
    writeContract({
      address: CONTRACT_ADDRESSES.shieldCore,
      abi: SHIELD_CORE_ABI,
      functionName: 'executeShieldConfigUpdate',
    })
  }

  return {
    proposeUpdate,
    executeUpdate,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  }
}

export function useWhitelist() {
  const { address } = useAccount()
  const { writeContract, data: hash, isPending, error } = useWriteContract()

  const { data: whitelistedContracts, refetch } = useReadContract({
    address: CONTRACT_ADDRESSES.shieldCore,
    abi: SHIELD_CORE_ABI,
    functionName: 'getWhitelistedContracts',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
    },
  })

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const addToWhitelist = async (contractAddr: `0x${string}`) => {
    writeContract({
      address: CONTRACT_ADDRESSES.shieldCore,
      abi: SHIELD_CORE_ABI,
      functionName: 'addWhitelistedContract',
      args: [contractAddr],
    })
  }

  const removeFromWhitelist = async (contractAddr: `0x${string}`) => {
    writeContract({
      address: CONTRACT_ADDRESSES.shieldCore,
      abi: SHIELD_CORE_ABI,
      functionName: 'removeWhitelistedContract',
      args: [contractAddr],
    })
  }

  return {
    whitelistedContracts: whitelistedContracts as `0x${string}`[] | undefined,
    addToWhitelist,
    removeFromWhitelist,
    refetch,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
  }
}
