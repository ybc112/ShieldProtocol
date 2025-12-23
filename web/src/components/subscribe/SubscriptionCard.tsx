'use client'

import { Play, Pause, XCircle, Clock, ExternalLink } from 'lucide-react'
import { Card, CardContent, Button, Badge, Progress } from '@/components/ui'
import {
  useSubscription,
  usePauseSubscription,
  useResumeSubscription,
  useCancelSubscription,
  SubscriptionStatus,
  getBillingPeriodLabel,
  getSubscriptionStatusLabel,
  getSubscriptionStatusColor,
} from '@/hooks/useSubscription'
import { getTokenByAddress } from '@/types'
import { formatUnits } from 'viem'

interface SubscriptionCardProps {
  subscriptionId: `0x${string}`
  isRecipientView?: boolean
  onUpdate?: () => void
}

export function SubscriptionCard({
  subscriptionId,
  isRecipientView = false,
  onUpdate,
}: SubscriptionCardProps) {
  const { subscription, isLoading, refetch } = useSubscription(subscriptionId)
  const { pauseSubscription, isPending: isPausing } = usePauseSubscription()
  const { resumeSubscription, isPending: isResuming } = useResumeSubscription()
  const { cancelSubscription, isPending: isCancelling } = useCancelSubscription()

  if (isLoading || !subscription) {
    return (
      <Card className="animate-pulse">
        <CardContent className="p-6">
          <div className="h-6 w-32 bg-gray-700 rounded mb-4" />
          <div className="h-4 w-full bg-gray-800 rounded" />
        </CardContent>
      </Card>
    )
  }

  const token = getTokenByAddress(subscription.token)
  const isActive = subscription.status === SubscriptionStatus.Active
  const isPaused = subscription.status === SubscriptionStatus.Paused
  const canModify = !isRecipientView && (isActive || isPaused)
  const progress = subscription.maxPayments > 0n
    ? Number(subscription.paymentsCompleted) / Number(subscription.maxPayments) * 100
    : 0

  const formatAmount = (amount: bigint) => {
    return parseFloat(formatUnits(amount, token?.decimals || 6)).toLocaleString(undefined, {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    })
  }

  const formatAddress = (addr: string) => {
    return `${addr.slice(0, 6)}...${addr.slice(-4)}`
  }

  const getTimeUntilNext = () => {
    const now = Math.floor(Date.now() / 1000)
    const next = Number(subscription.nextPaymentTime)
    const diff = next - now

    if (diff <= 0) return 'Due now'
    if (diff < 60) return `${diff}s`
    if (diff < 3600) return `${Math.floor(diff / 60)}m`
    if (diff < 86400) return `${Math.floor(diff / 3600)}h`
    return `${Math.floor(diff / 86400)}d`
  }

  const handlePause = async () => {
    await pauseSubscription(subscriptionId)
    refetch()
    onUpdate?.()
  }

  const handleResume = async () => {
    await resumeSubscription(subscriptionId)
    refetch()
    onUpdate?.()
  }

  const handleCancel = async () => {
    if (confirm('Are you sure you want to cancel this subscription?')) {
      await cancelSubscription(subscriptionId)
      refetch()
      onUpdate?.()
    }
  }

  return (
    <Card className={!isActive && !isPaused ? 'opacity-75' : ''}>
      <CardContent className="p-6">
        <div className="flex items-start justify-between mb-4">
          <div>
            <div className="flex items-center space-x-2 mb-1">
              <span className="text-lg font-semibold">
                {formatAmount(subscription.amount)} {token?.symbol}
              </span>
              <Badge variant={getSubscriptionStatusColor(subscription.status)}>
                {getSubscriptionStatusLabel(subscription.status)}
              </Badge>
            </div>
            <p className="text-sm text-gray-400">
              {getBillingPeriodLabel(subscription.billingPeriod)} to{' '}
              <a
                href={`https://sepolia.etherscan.io/address/${isRecipientView ? subscription.subscriber : subscription.recipient}`}
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary-400 hover:underline"
              >
                {formatAddress(isRecipientView ? subscription.subscriber : subscription.recipient)}
                <ExternalLink className="inline h-3 w-3 ml-1" />
              </a>
            </p>
          </div>

          {/* Actions */}
          {canModify && (
            <div className="flex items-center space-x-1">
              {isActive ? (
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={handlePause}
                  loading={isPausing}
                >
                  <Pause className="h-4 w-4" />
                </Button>
              ) : isPaused ? (
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={handleResume}
                  loading={isResuming}
                >
                  <Play className="h-4 w-4" />
                </Button>
              ) : null}
              <Button
                size="sm"
                variant="ghost"
                onClick={handleCancel}
                loading={isCancelling}
                className="text-red-400 hover:text-red-300"
              >
                <XCircle className="h-4 w-4" />
              </Button>
            </div>
          )}
        </div>

        {/* Progress (if max payments set) */}
        {subscription.maxPayments > 0n && (
          <div className="mb-4">
            <div className="flex justify-between text-sm mb-1">
              <span className="text-gray-400">Payments</span>
              <span className="text-gray-300">
                {subscription.paymentsCompleted.toString()} / {subscription.maxPayments.toString()}
              </span>
            </div>
            <Progress value={progress} className="h-2" />
          </div>
        )}

        {/* Details */}
        <div className="grid grid-cols-2 gap-3 text-sm">
          <div>
            <p className="text-gray-500">Next Payment</p>
            <p className="text-gray-300 flex items-center">
              <Clock className="h-3.5 w-3.5 mr-1" />
              {isActive ? getTimeUntilNext() : '-'}
            </p>
          </div>
          <div>
            <p className="text-gray-500">Total Paid</p>
            <p className="text-gray-300">
              {formatAmount(subscription.amount * subscription.paymentsCompleted)} {token?.symbol}
            </p>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}
