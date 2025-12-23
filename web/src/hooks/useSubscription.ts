'use client'

import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { SUBSCRIPTION_MANAGER_ABI, CONTRACT_ADDRESSES } from '@/lib/contracts'

// Enums
export enum SubscriptionStatus {
  Active = 0,
  Paused = 1,
  Cancelled = 2,
  Expired = 3,
}

export enum BillingPeriod {
  Daily = 0,
  Weekly = 1,
  Monthly = 2,
  Yearly = 3,
}

// Types
export interface Subscription {
  subscriptionId: `0x${string}`
  subscriber: `0x${string}`
  recipient: `0x${string}`
  token: `0x${string}`
  amount: bigint
  billingPeriod: BillingPeriod
  nextPaymentTime: bigint
  paymentsCompleted: bigint
  maxPayments: bigint
  status: SubscriptionStatus
  createdAt: bigint
  cancelledAt: bigint
}

export interface CreateSubscriptionParams {
  recipient: `0x${string}`
  token: `0x${string}`
  amount: bigint
  billingPeriod: BillingPeriod
  maxPayments: bigint
  executeFirstPayment: boolean
}

// Get user's subscriptions as subscriber
export function useSubscriberSubscriptions() {
  const { address } = useAccount()

  const { data: subscriptionIds, isLoading, refetch } = useReadContract({
    address: CONTRACT_ADDRESSES.subscriptionManager,
    abi: SUBSCRIPTION_MANAGER_ABI,
    functionName: 'getSubscriberSubscriptions',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
    },
  })

  return {
    subscriptionIds: subscriptionIds as `0x${string}`[] | undefined,
    isLoading,
    refetch,
  }
}

// Get user's subscriptions as recipient (creator)
export function useRecipientSubscriptions() {
  const { address } = useAccount()

  const { data: subscriptionIds, isLoading, refetch } = useReadContract({
    address: CONTRACT_ADDRESSES.subscriptionManager,
    abi: SUBSCRIPTION_MANAGER_ABI,
    functionName: 'getRecipientSubscriptions',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
    },
  })

  return {
    subscriptionIds: subscriptionIds as `0x${string}`[] | undefined,
    isLoading,
    refetch,
  }
}

// Get subscription details
export function useSubscription(subscriptionId: `0x${string}` | undefined) {
  const { data, isLoading, refetch } = useReadContract({
    address: CONTRACT_ADDRESSES.subscriptionManager,
    abi: SUBSCRIPTION_MANAGER_ABI,
    functionName: 'getSubscription',
    args: subscriptionId ? [subscriptionId] : undefined,
    query: {
      enabled: !!subscriptionId,
    },
  })

  return {
    subscription: data as Subscription | undefined,
    isLoading,
    refetch,
  }
}

// Get monthly subscription cost
export function useMonthlySubscriptionCost() {
  const { address } = useAccount()

  const { data, isLoading } = useReadContract({
    address: CONTRACT_ADDRESSES.subscriptionManager,
    abi: SUBSCRIPTION_MANAGER_ABI,
    functionName: 'getMonthlySubscriptionCost',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address,
    },
  })

  return {
    monthlyCost: data as bigint | undefined,
    isLoading,
  }
}

// Create subscription
export function useCreateSubscription() {
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const createSubscription = async (params: CreateSubscriptionParams) => {
    writeContract({
      address: CONTRACT_ADDRESSES.subscriptionManager,
      abi: SUBSCRIPTION_MANAGER_ABI,
      functionName: 'createSubscription',
      args: [params],
    })
  }

  return {
    createSubscription,
    hash,
    isPending,
    isConfirming,
    isSuccess,
    error,
    reset,
  }
}

// Pause subscription
export function usePauseSubscription() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const pauseSubscription = async (subscriptionId: `0x${string}`) => {
    writeContract({
      address: CONTRACT_ADDRESSES.subscriptionManager,
      abi: SUBSCRIPTION_MANAGER_ABI,
      functionName: 'pauseSubscription',
      args: [subscriptionId],
    })
  }

  return {
    pauseSubscription,
    isPending: isPending || isConfirming,
    isSuccess,
    error,
  }
}

// Resume subscription
export function useResumeSubscription() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const resumeSubscription = async (subscriptionId: `0x${string}`) => {
    writeContract({
      address: CONTRACT_ADDRESSES.subscriptionManager,
      abi: SUBSCRIPTION_MANAGER_ABI,
      functionName: 'resumeSubscription',
      args: [subscriptionId],
    })
  }

  return {
    resumeSubscription,
    isPending: isPending || isConfirming,
    isSuccess,
    error,
  }
}

// Cancel subscription
export function useCancelSubscription() {
  const { writeContract, data: hash, isPending, error } = useWriteContract()

  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  const cancelSubscription = async (subscriptionId: `0x${string}`) => {
    writeContract({
      address: CONTRACT_ADDRESSES.subscriptionManager,
      abi: SUBSCRIPTION_MANAGER_ABI,
      functionName: 'cancelSubscription',
      args: [subscriptionId],
    })
  }

  return {
    cancelSubscription,
    isPending: isPending || isConfirming,
    isSuccess,
    error,
  }
}

// Helpers
export function getBillingPeriodLabel(period: BillingPeriod): string {
  switch (period) {
    case BillingPeriod.Daily:
      return 'Daily'
    case BillingPeriod.Weekly:
      return 'Weekly'
    case BillingPeriod.Monthly:
      return 'Monthly'
    case BillingPeriod.Yearly:
      return 'Yearly'
    default:
      return 'Unknown'
  }
}

export function getSubscriptionStatusLabel(status: SubscriptionStatus): string {
  switch (status) {
    case SubscriptionStatus.Active:
      return 'Active'
    case SubscriptionStatus.Paused:
      return 'Paused'
    case SubscriptionStatus.Cancelled:
      return 'Cancelled'
    case SubscriptionStatus.Expired:
      return 'Expired'
    default:
      return 'Unknown'
  }
}

export function getSubscriptionStatusColor(status: SubscriptionStatus): 'success' | 'warning' | 'destructive' | 'secondary' {
  switch (status) {
    case SubscriptionStatus.Active:
      return 'success'
    case SubscriptionStatus.Paused:
      return 'warning'
    case SubscriptionStatus.Cancelled:
      return 'destructive'
    case SubscriptionStatus.Expired:
      return 'secondary'
    default:
      return 'secondary'
  }
}
