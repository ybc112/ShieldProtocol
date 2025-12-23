'use client'

import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { ERC20_ABI, CONTRACT_ADDRESSES } from '@/lib/contracts'
import { maxUint256 } from 'viem'

export function useTokenBalance(tokenAddress: `0x${string}` | undefined) {
  const { address } = useAccount()

  const { data: balance, isLoading, refetch } = useReadContract({
    address: tokenAddress,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: {
      enabled: !!tokenAddress && !!address,
    },
  })

  return {
    balance: balance as bigint | undefined,
    isLoading,
    refetch,
  }
}

export function useTokenAllowance(
  tokenAddress: `0x${string}` | undefined,
  spenderAddress: `0x${string}` | undefined
) {
  const { address } = useAccount()

  const { data: allowance, isLoading, refetch } = useReadContract({
    address: tokenAddress,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: address && spenderAddress ? [address, spenderAddress] : undefined,
    query: {
      enabled: !!tokenAddress && !!address && !!spenderAddress,
    },
  })

  return {
    allowance: allowance as bigint | undefined,
    isLoading,
    refetch,
  }
}

export function useApproveToken() {
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const approve = async (
    tokenAddress: `0x${string}`,
    spenderAddress: `0x${string}`,
    amount: bigint = maxUint256
  ) => {
    writeContract({
      address: tokenAddress,
      abi: ERC20_ABI,
      functionName: 'approve',
      args: [spenderAddress, amount],
    })
  }

  return {
    approve,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
    reset,
  }
}

export function useDCAExecutorAllowance(tokenAddress: `0x${string}` | undefined) {
  return useTokenAllowance(tokenAddress, CONTRACT_ADDRESSES.dcaExecutor)
}
