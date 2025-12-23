'use client'

import { useParams, useRouter } from 'next/navigation'
import { useAccount } from 'wagmi'
import { ArrowLeft, Play, Pause, XCircle, Clock, TrendingUp, BarChart3, RefreshCw } from 'lucide-react'
import Link from 'next/link'
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
  Button,
  Badge,
  Progress,
} from '@/components/ui'
import { ConnectPrompt } from '@/components/dashboard/ConnectPrompt'
import {
  useStrategy,
  useStrategyStats,
  usePauseStrategy,
  useResumeStrategy,
  useCancelStrategy,
} from '@/hooks'
import {
  StrategyStatus,
  getTokenByAddress,
  getStatusLabel,
  getStatusColor,
} from '@/types'
import { formatUnits } from 'viem'

export default function StrategyDetailPage() {
  const params = useParams()
  const router = useRouter()
  const { isConnected } = useAccount()
  const strategyId = params.id as `0x${string}`

  const { strategy, isLoading, refetch } = useStrategy(strategyId)
  const { stats } = useStrategyStats(strategyId)
  const { pauseStrategy, isPending: isPausing } = usePauseStrategy()
  const { resumeStrategy, isPending: isResuming } = useResumeStrategy()
  const { cancelStrategy, isPending: isCancelling } = useCancelStrategy()

  if (!isConnected) {
    return <ConnectPrompt />
  }

  if (isLoading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <RefreshCw className="h-8 w-8 animate-spin text-primary-400" />
      </div>
    )
  }

  if (!strategy) {
    return (
      <div className="space-y-6">
        <Link href="/strategies" className="inline-flex items-center text-gray-400 hover:text-white">
          <ArrowLeft className="h-4 w-4 mr-2" />
          Back to Strategies
        </Link>
        <Card>
          <CardContent className="p-8 text-center">
            <p className="text-gray-400">Strategy not found</p>
          </CardContent>
        </Card>
      </div>
    )
  }

  const sourceToken = getTokenByAddress(strategy.sourceToken)
  const targetToken = getTokenByAddress(strategy.targetToken)
  const progress = Number(strategy.executionsCompleted) / Number(strategy.totalExecutions) * 100
  const isActive = strategy.status === StrategyStatus.Active
  const isPaused = strategy.status === StrategyStatus.Paused
  const canModify = isActive || isPaused

  const formatAmount = (amount: bigint, decimals: number) => {
    return parseFloat(formatUnits(amount, decimals)).toLocaleString(undefined, {
      minimumFractionDigits: 2,
      maximumFractionDigits: 6,
    })
  }

  const formatTime = (timestamp: bigint) => {
    const date = new Date(Number(timestamp) * 1000)
    return date.toLocaleString()
  }

  const getTimeUntilNext = () => {
    const now = Math.floor(Date.now() / 1000)
    const next = Number(strategy.nextExecutionTime)
    const diff = next - now

    if (diff <= 0) return 'Ready to execute'
    if (diff < 60) return `${diff} seconds`
    if (diff < 3600) return `${Math.floor(diff / 60)} minutes`
    if (diff < 86400) return `${Math.floor(diff / 3600)} hours`
    return `${Math.floor(diff / 86400)} days`
  }

  const handlePause = async () => {
    await pauseStrategy(strategyId)
    refetch()
  }

  const handleResume = async () => {
    await resumeStrategy(strategyId)
    refetch()
  }

  const handleCancel = async () => {
    if (confirm('Are you sure you want to cancel this strategy? This action cannot be undone.')) {
      await cancelStrategy(strategyId)
      refetch()
    }
  }

  return (
    <div className="space-y-6">
      {/* Back Button */}
      <Link href="/strategies" className="inline-flex items-center text-gray-400 hover:text-white transition-colors">
        <ArrowLeft className="h-4 w-4 mr-2" />
        Back to Strategies
      </Link>

      {/* Header */}
      <div className="flex items-start justify-between">
        <div>
          <div className="flex items-center space-x-3">
            <h1 className="text-3xl font-bold">
              {sourceToken?.symbol} → {targetToken?.symbol}
            </h1>
            <Badge variant={getStatusColor(strategy.status) as 'success' | 'warning' | 'destructive' | 'secondary'}>
              {getStatusLabel(strategy.status)}
            </Badge>
          </div>
          <p className="text-gray-400 mt-1 text-sm font-mono">
            ID: {strategyId.slice(0, 10)}...{strategyId.slice(-8)}
          </p>
        </div>

        {/* Action Buttons */}
        {canModify && (
          <div className="flex items-center space-x-2">
            {isActive ? (
              <Button
                variant="outline"
                onClick={handlePause}
                loading={isPausing}
              >
                <Pause className="h-4 w-4 mr-2" />
                Pause
              </Button>
            ) : isPaused ? (
              <Button
                variant="outline"
                onClick={handleResume}
                loading={isResuming}
              >
                <Play className="h-4 w-4 mr-2" />
                Resume
              </Button>
            ) : null}
            <Button
              variant="destructive"
              onClick={handleCancel}
              loading={isCancelling}
            >
              <XCircle className="h-4 w-4 mr-2" />
              Cancel
            </Button>
          </div>
        )}
      </div>

      {/* Progress Card */}
      <Card>
        <CardHeader>
          <CardTitle className="text-lg">Execution Progress</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            <Progress value={progress} className="h-3" />
            <div className="flex justify-between text-sm">
              <span className="text-gray-400">
                {Number(strategy.executionsCompleted)} / {Number(strategy.totalExecutions)} executions
              </span>
              <span className="text-primary-400 font-medium">
                {progress.toFixed(1)}%
              </span>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Stats Grid */}
      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-4">
        <Card>
          <CardContent className="p-6">
            <div className="flex items-center space-x-3">
              <div className="p-2 rounded-lg bg-primary-600/20">
                <TrendingUp className="h-5 w-5 text-primary-400" />
              </div>
              <div>
                <p className="text-sm text-gray-400">Amount Per Execution</p>
                <p className="text-xl font-bold">
                  {formatAmount(strategy.amountPerExecution, sourceToken?.decimals || 18)} {sourceToken?.symbol}
                </p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-6">
            <div className="flex items-center space-x-3">
              <div className="p-2 rounded-lg bg-green-600/20">
                <Clock className="h-5 w-5 text-green-400" />
              </div>
              <div>
                <p className="text-sm text-gray-400">Next Execution</p>
                <p className="text-xl font-bold">
                  {isActive ? getTimeUntilNext() : '-'}
                </p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-6">
            <div className="flex items-center space-x-3">
              <div className="p-2 rounded-lg bg-blue-600/20">
                <BarChart3 className="h-5 w-5 text-blue-400" />
              </div>
              <div>
                <p className="text-sm text-gray-400">Total Invested</p>
                <p className="text-xl font-bold">
                  {stats ? formatAmount(stats.totalIn, sourceToken?.decimals || 18) : '0'} {sourceToken?.symbol}
                </p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-6">
            <div className="flex items-center space-x-3">
              <div className="p-2 rounded-lg bg-purple-600/20">
                <TrendingUp className="h-5 w-5 text-purple-400" />
              </div>
              <div>
                <p className="text-sm text-gray-400">Total Received</p>
                <p className="text-xl font-bold">
                  {stats ? formatAmount(stats.totalOut, targetToken?.decimals || 18) : '0'} {targetToken?.symbol}
                </p>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Strategy Details */}
      <Card>
        <CardHeader>
          <CardTitle>Strategy Details</CardTitle>
          <CardDescription>Configuration and execution parameters</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid gap-4 md:grid-cols-2">
            <div className="space-y-4">
              <div className="flex justify-between py-2 border-b border-gray-800">
                <span className="text-gray-400">Source Token</span>
                <span className="font-medium">{sourceToken?.name} ({sourceToken?.symbol})</span>
              </div>
              <div className="flex justify-between py-2 border-b border-gray-800">
                <span className="text-gray-400">Target Token</span>
                <span className="font-medium">{targetToken?.name} ({targetToken?.symbol})</span>
              </div>
              <div className="flex justify-between py-2 border-b border-gray-800">
                <span className="text-gray-400">Interval</span>
                <span className="font-medium">
                  {Number(strategy.intervalSeconds) === 3600 && 'Hourly'}
                  {Number(strategy.intervalSeconds) === 86400 && 'Daily'}
                  {Number(strategy.intervalSeconds) === 604800 && 'Weekly'}
                  {Number(strategy.intervalSeconds) === 2592000 && 'Monthly'}
                  {![3600, 86400, 604800, 2592000].includes(Number(strategy.intervalSeconds)) &&
                    `${Number(strategy.intervalSeconds)} seconds`}
                </span>
              </div>
              <div className="flex justify-between py-2 border-b border-gray-800">
                <span className="text-gray-400">Pool Fee</span>
                <span className="font-medium">{strategy.poolFee / 10000}%</span>
              </div>
            </div>
            <div className="space-y-4">
              <div className="flex justify-between py-2 border-b border-gray-800">
                <span className="text-gray-400">Created At</span>
                <span className="font-medium">{formatTime(strategy.createdAt)}</span>
              </div>
              <div className="flex justify-between py-2 border-b border-gray-800">
                <span className="text-gray-400">Last Updated</span>
                <span className="font-medium">{formatTime(strategy.updatedAt)}</span>
              </div>
              <div className="flex justify-between py-2 border-b border-gray-800">
                <span className="text-gray-400">Min Amount Out</span>
                <span className="font-medium">
                  {formatAmount(strategy.minAmountOut, targetToken?.decimals || 18)} {targetToken?.symbol}
                </span>
              </div>
              <div className="flex justify-between py-2 border-b border-gray-800">
                <span className="text-gray-400">Average Price</span>
                <span className="font-medium">
                  {stats && stats.averagePrice > 0n
                    ? formatAmount(stats.averagePrice, 18)
                    : '-'}
                </span>
              </div>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
