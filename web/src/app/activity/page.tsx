'use client'

import { useAccount } from 'wagmi'
import {
  History,
  ArrowUpRight,
  ArrowDownRight,
  Shield,
  TrendingUp,
  AlertTriangle,
  ExternalLink,
  RefreshCw,
  CreditCard,
  PlayCircle,
  PauseCircle,
  XCircle,
} from 'lucide-react'
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
  Badge,
  Button,
} from '@/components/ui'
import { ConnectPrompt } from '@/components/dashboard/ConnectPrompt'
import { useActivityLogs, type ActivityType } from '@/hooks/useActivity'
import { getTokenByAddress } from '@/types'
import { formatTokenAmount, shortenAddress } from '@/lib/utils'

const activityConfig: Record<ActivityType, { icon: typeof Shield; color: string; bgColor: string; label: string }> = {
  shield_activated: { icon: Shield, color: 'text-green-400', bgColor: 'bg-green-600/20', label: 'Shield Activated' },
  shield_deactivated: { icon: Shield, color: 'text-gray-400', bgColor: 'bg-gray-600/20', label: 'Shield Deactivated' },
  emergency_enabled: { icon: AlertTriangle, color: 'text-red-400', bgColor: 'bg-red-600/20', label: 'Emergency Mode Enabled' },
  emergency_disabled: { icon: AlertTriangle, color: 'text-green-400', bgColor: 'bg-green-600/20', label: 'Emergency Mode Disabled' },
  strategy_created: { icon: TrendingUp, color: 'text-blue-400', bgColor: 'bg-blue-600/20', label: 'Strategy Created' },
  strategy_executed: { icon: PlayCircle, color: 'text-primary-400', bgColor: 'bg-primary-600/20', label: 'DCA Executed' },
  strategy_paused: { icon: PauseCircle, color: 'text-yellow-400', bgColor: 'bg-yellow-600/20', label: 'Strategy Paused' },
  strategy_resumed: { icon: PlayCircle, color: 'text-green-400', bgColor: 'bg-green-600/20', label: 'Strategy Resumed' },
  strategy_cancelled: { icon: XCircle, color: 'text-red-400', bgColor: 'bg-red-600/20', label: 'Strategy Cancelled' },
  subscription_created: { icon: CreditCard, color: 'text-blue-400', bgColor: 'bg-blue-600/20', label: 'Subscription Created' },
  payment_executed: { icon: ArrowUpRight, color: 'text-green-400', bgColor: 'bg-green-600/20', label: 'Payment Executed' },
  subscription_cancelled: { icon: XCircle, color: 'text-red-400', bgColor: 'bg-red-600/20', label: 'Subscription Cancelled' },
}

export default function ActivityPage() {
  const { isConnected } = useAccount()
  const { activities, isLoading, refetch } = useActivityLogs()

  if (!isConnected) {
    return <ConnectPrompt />
  }

  const formatTime = (timestamp: number) => {
    if (!timestamp || timestamp === 0) return 'Recently'
    const diff = Date.now() - timestamp
    if (diff < 60000) return 'Just now'
    if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`
    if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`
    if (diff < 604800000) return `${Math.floor(diff / 86400000)}d ago`
    return new Date(timestamp).toLocaleDateString()
  }

  const formatDetail = (key: string, value: string | number | bigint) => {
    // Format token amounts
    if (key === 'dailyLimit' || key === 'singleTxLimit' || key === 'amount' || key === 'amountPerExecution') {
      return `${formatTokenAmount(BigInt(value.toString()), 6)} USDC`
    }
    if (key === 'amountIn') {
      return `${formatTokenAmount(BigInt(value.toString()), 6)} USDC`
    }
    if (key === 'amountOut') {
      return `${formatTokenAmount(BigInt(value.toString()), 18)} WETH`
    }
    // Format addresses
    if (key === 'sourceToken' || key === 'targetToken' || key === 'recipient') {
      const token = getTokenByAddress(value.toString())
      if (token) return token.symbol
      return shortenAddress(value.toString())
    }
    // Format strategy/subscription IDs
    if (key === 'strategyId' || key === 'subscriptionId') {
      return shortenAddress(value.toString(), 6)
    }
    return value.toString()
  }

  const getDetailLabel = (key: string) => {
    const labels: Record<string, string> = {
      dailyLimit: 'Daily Limit',
      singleTxLimit: 'Tx Limit',
      strategyId: 'Strategy',
      subscriptionId: 'Subscription',
      sourceToken: 'From',
      targetToken: 'To',
      amountPerExecution: 'Per Exec',
      totalExecutions: 'Total Execs',
      amountIn: 'Spent',
      amountOut: 'Received',
      executionsCompleted: 'Completed',
      amount: 'Amount',
      paymentNumber: 'Payment #',
      recipient: 'To',
    }
    return labels[key] || key
  }

  return (
    <div className="space-y-8">
      {/* Page Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold">Activity Log</h1>
          <p className="text-gray-400 mt-1">
            Track your Shield Protocol activities and transactions
          </p>
        </div>
        <Button variant="outline" onClick={() => refetch()} disabled={isLoading}>
          <RefreshCw className={`h-4 w-4 mr-2 ${isLoading ? 'animate-spin' : ''}`} />
          Refresh
        </Button>
      </div>

      {/* Stats */}
      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardContent className="p-4">
            <p className="text-sm text-gray-400">Total Events</p>
            <p className="text-2xl font-bold">{activities.length}</p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <p className="text-sm text-gray-400">DCA Executions</p>
            <p className="text-2xl font-bold text-primary-400">
              {activities.filter(a => a.type === 'strategy_executed').length}
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <p className="text-sm text-gray-400">Strategies Created</p>
            <p className="text-2xl font-bold text-blue-400">
              {activities.filter(a => a.type === 'strategy_created').length}
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <p className="text-sm text-gray-400">Payments</p>
            <p className="text-2xl font-bold text-green-400">
              {activities.filter(a => a.type === 'payment_executed').length}
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Activity List */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center space-x-2">
            <History className="h-5 w-5 text-primary-400" />
            <span>Recent Activity</span>
          </CardTitle>
          <CardDescription>
            Your latest transactions and strategy executions from the blockchain
          </CardDescription>
        </CardHeader>
        <CardContent>
          {isLoading ? (
            <div className="flex items-center justify-center py-12">
              <RefreshCw className="h-8 w-8 animate-spin text-primary-400" />
            </div>
          ) : activities.length === 0 ? (
            <div className="text-center py-12">
              <History className="h-12 w-12 text-gray-600 mx-auto mb-4" />
              <p className="text-gray-400">No activity yet</p>
              <p className="text-sm text-gray-500 mt-1">
                Your transactions and strategy executions will appear here
              </p>
            </div>
          ) : (
            <div className="space-y-4">
              {activities.map((activity) => {
                const config = activityConfig[activity.type]
                const Icon = config.icon

                return (
                  <div
                    key={activity.id}
                    className="flex items-start space-x-4 p-4 rounded-lg bg-gray-800/50 hover:bg-gray-800 transition-colors"
                  >
                    <div className={`p-2.5 rounded-lg ${config.bgColor}`}>
                      <Icon className={`h-5 w-5 ${config.color}`} />
                    </div>

                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between mb-1">
                        <p className="font-medium">{config.label}</p>
                        <span className="text-sm text-gray-500">
                          {formatTime(activity.timestamp)}
                        </span>
                      </div>

                      {Object.keys(activity.details).length > 0 && (
                        <div className="flex flex-wrap gap-2 mt-2">
                          {Object.entries(activity.details)
                            .filter(([_, value]) => value && value.toString() !== '0' && value.toString() !== '')
                            .map(([key, value]) => (
                              <Badge key={key} variant="secondary" className="text-xs">
                                {getDetailLabel(key)}: {formatDetail(key, value)}
                              </Badge>
                            ))}
                        </div>
                      )}

                      <a
                        href={`https://sepolia.etherscan.io/tx/${activity.txHash}`}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="inline-flex items-center text-xs text-gray-500 hover:text-primary-400 mt-2"
                      >
                        View on Etherscan
                        <ExternalLink className="h-3 w-3 ml-1" />
                      </a>
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
