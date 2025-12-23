'use client'

import { useAccount } from 'wagmi'
import { formatUnits } from 'viem'
import {
  BarChart3,
  TrendingUp,
  DollarSign,
  Activity,
  PieChart,
  ArrowUpRight,
  RefreshCw,
} from 'lucide-react'
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
  Badge,
  Progress,
  Button,
} from '@/components/ui'
import { ConnectPrompt } from '@/components/dashboard/ConnectPrompt'
import { useUserStrategies, useStrategy, useStrategyStats } from '@/hooks'
import { useDCAStats, useActivityLogs } from '@/hooks/useActivity'
import { formatTokenAmount } from '@/lib/utils'
import { StrategyStatus, getTokenByAddress } from '@/types'

export default function AnalyticsPage() {
  const { isConnected } = useAccount()
  const { strategyIds, refetch: refetchStrategies } = useUserStrategies()
  const { stats: dcaStats, isLoading: isLoadingStats, refetch: refetchStats } = useDCAStats()
  const { activities } = useActivityLogs()

  if (!isConnected) {
    return <ConnectPrompt />
  }

  const hasStrategies = strategyIds && strategyIds.length > 0
  const hasExecutions = dcaStats.totalExecutions > 0

  // Calculate stats
  const totalInvested = hasExecutions ? formatTokenAmount(dcaStats.totalAmountIn, 6) : '0'
  const totalReceived = hasExecutions ? formatTokenAmount(dcaStats.totalAmountOut, 18) : '0'

  // Calculate average price (USDC per WETH)
  const averagePrice = hasExecutions && dcaStats.totalAmountOut > 0n
    ? Number(dcaStats.totalAmountIn) / Number(dcaStats.totalAmountOut) * 1e12
    : 0

  const handleRefresh = () => {
    refetchStrategies()
    refetchStats()
  }

  // Count activity types
  const executionCount = activities.filter(a => a.type === 'strategy_executed').length
  const strategyCount = activities.filter(a => a.type === 'strategy_created').length

  return (
    <div className="space-y-8">
      {/* Page Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold">Analytics</h1>
          <p className="text-gray-400 mt-1">
            Track your investment performance and strategy metrics
          </p>
        </div>
        <Button variant="outline" onClick={handleRefresh} disabled={isLoadingStats}>
          <RefreshCw className={`h-4 w-4 mr-2 ${isLoadingStats ? 'animate-spin' : ''}`} />
          Refresh
        </Button>
      </div>

      {/* Overview Stats */}
      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-4">
        <Card>
          <CardContent className="p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-400">Total Invested</p>
                <p className="text-2xl font-bold mt-1">
                  {totalInvested} <span className="text-sm text-gray-400">USDC</span>
                </p>
              </div>
              <div className="p-3 rounded-lg bg-blue-600/20">
                <DollarSign className="h-6 w-6 text-blue-400" />
              </div>
            </div>
            {hasExecutions && (
              <div className="flex items-center mt-3 text-sm">
                <ArrowUpRight className="h-4 w-4 text-green-400 mr-1" />
                <span className="text-green-400">From {dcaStats.totalExecutions} executions</span>
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-400">Total Received</p>
                <p className="text-2xl font-bold mt-1">
                  {totalReceived} <span className="text-sm text-gray-400">WETH</span>
                </p>
              </div>
              <div className="p-3 rounded-lg bg-green-600/20">
                <TrendingUp className="h-6 w-6 text-green-400" />
              </div>
            </div>
            {hasExecutions && averagePrice > 0 && (
              <div className="flex items-center mt-3 text-sm">
                <span className="text-gray-400">
                  Avg Price: ${averagePrice.toFixed(2)}
                </span>
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-400">Total Executions</p>
                <p className="text-2xl font-bold mt-1">
                  {dcaStats.totalExecutions}
                </p>
              </div>
              <div className="p-3 rounded-lg bg-purple-600/20">
                <Activity className="h-6 w-6 text-purple-400" />
              </div>
            </div>
            <div className="flex items-center mt-3 text-sm">
              <span className="text-green-400">{dcaStats.successRate}%</span>
              <span className="text-gray-500 ml-1">success rate</span>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-400">Active Strategies</p>
                <p className="text-2xl font-bold mt-1">
                  {strategyIds?.length || 0}
                </p>
              </div>
              <div className="p-3 rounded-lg bg-primary-600/20">
                <BarChart3 className="h-6 w-6 text-primary-400" />
              </div>
            </div>
            <div className="flex items-center mt-3 text-sm">
              <span className="text-gray-400">
                {strategyCount} total created
              </span>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Strategy Details */}
      <div className="grid gap-6 lg:grid-cols-2">
        {/* Strategies Overview */}
        <Card>
          <CardHeader>
            <CardTitle>Strategies Overview</CardTitle>
            <CardDescription>Performance of your active strategies</CardDescription>
          </CardHeader>
          <CardContent>
            {!hasStrategies ? (
              <div className="h-64 flex items-center justify-center text-gray-500">
                <div className="text-center">
                  <BarChart3 className="h-12 w-12 mx-auto mb-2 opacity-50" />
                  <p>No strategies yet</p>
                  <p className="text-sm">Create a strategy to see analytics</p>
                </div>
              </div>
            ) : (
              <div className="space-y-4">
                {strategyIds?.slice(0, 5).map((id) => (
                  <StrategyRow key={id} strategyId={id} />
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Execution History Chart */}
        <Card>
          <CardHeader>
            <CardTitle>Execution Summary</CardTitle>
            <CardDescription>Breakdown of your DCA activity</CardDescription>
          </CardHeader>
          <CardContent>
            {!hasExecutions ? (
              <div className="h-64 flex items-center justify-center text-gray-500">
                <div className="text-center">
                  <PieChart className="h-12 w-12 mx-auto mb-2 opacity-50" />
                  <p>No executions yet</p>
                  <p className="text-sm">Execute a DCA to see data</p>
                </div>
              </div>
            ) : (
              <div className="space-y-6 py-4">
                <div>
                  <div className="flex justify-between mb-2">
                    <span className="text-sm text-gray-400">USDC Invested</span>
                    <span className="text-sm font-medium">{totalInvested} USDC</span>
                  </div>
                  <Progress value={100} className="h-3" />
                </div>
                <div>
                  <div className="flex justify-between mb-2">
                    <span className="text-sm text-gray-400">WETH Received</span>
                    <span className="text-sm font-medium">{totalReceived} WETH</span>
                  </div>
                  <div className="h-3 bg-gray-800 rounded-full overflow-hidden">
                    <div className="h-full w-full bg-blue-500 rounded-full" />
                  </div>
                </div>
                <div className="p-4 rounded-lg bg-gray-800/50">
                  <div className="flex items-center justify-between">
                    <span className="text-sm text-gray-400">Average Price</span>
                    <span className="text-lg font-bold text-primary-400">
                      ${averagePrice.toFixed(2)} <span className="text-sm text-gray-400">/ WETH</span>
                    </span>
                  </div>
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Performance Metrics */}
      <Card>
        <CardHeader>
          <CardTitle>DCA Performance Metrics</CardTitle>
          <CardDescription>Summary of your dollar-cost averaging performance</CardDescription>
        </CardHeader>
        <CardContent>
          {!hasExecutions ? (
            <div className="text-center py-8 text-gray-500">
              <TrendingUp className="h-12 w-12 mx-auto mb-2 opacity-50" />
              <p>No performance data yet</p>
              <p className="text-sm">Start a DCA strategy to track performance</p>
            </div>
          ) : (
            <div className="grid gap-6 md:grid-cols-4">
              <div className="p-4 rounded-lg bg-gray-800/50">
                <p className="text-sm text-gray-400 mb-2">Total Executions</p>
                <p className="text-2xl font-bold text-primary-400">{dcaStats.totalExecutions}</p>
                <p className="text-xs text-gray-500 mt-1">Successful swaps</p>
              </div>
              <div className="p-4 rounded-lg bg-gray-800/50">
                <p className="text-sm text-gray-400 mb-2">Total Invested</p>
                <p className="text-2xl font-bold">{totalInvested}</p>
                <p className="text-xs text-gray-500 mt-1">USDC</p>
              </div>
              <div className="p-4 rounded-lg bg-gray-800/50">
                <p className="text-sm text-gray-400 mb-2">Total Received</p>
                <p className="text-2xl font-bold text-green-400">{totalReceived}</p>
                <p className="text-xs text-gray-500 mt-1">WETH</p>
              </div>
              <div className="p-4 rounded-lg bg-gray-800/50">
                <p className="text-sm text-gray-400 mb-2">Avg Price</p>
                <p className="text-2xl font-bold">${averagePrice.toFixed(2)}</p>
                <p className="text-xs text-gray-500 mt-1">Per WETH</p>
              </div>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}

// Strategy row component
function StrategyRow({ strategyId }: { strategyId: `0x${string}` }) {
  const { strategy, isLoading } = useStrategy(strategyId)
  const { stats } = useStrategyStats(strategyId)

  if (isLoading || !strategy) {
    return (
      <div className="p-3 rounded-lg bg-gray-800/50 animate-pulse">
        <div className="h-4 w-32 bg-gray-700 rounded" />
      </div>
    )
  }

  const sourceToken = getTokenByAddress(strategy.sourceToken)
  const targetToken = getTokenByAddress(strategy.targetToken)
  const progress = Number(strategy.executionsCompleted) / Number(strategy.totalExecutions) * 100
  const isActive = strategy.status === StrategyStatus.Active

  return (
    <div className={`p-4 rounded-lg bg-gray-800/50 ${!isActive ? 'opacity-60' : ''}`}>
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center space-x-2">
          <span className="font-medium">
            {sourceToken?.symbol} → {targetToken?.symbol}
          </span>
          <Badge variant={isActive ? 'success' : 'secondary'} className="text-xs">
            {isActive ? 'Active' : 'Paused'}
          </Badge>
        </div>
        <span className="text-sm text-gray-400">
          {Number(strategy.executionsCompleted)}/{Number(strategy.totalExecutions)}
        </span>
      </div>
      <Progress value={progress} className="h-2" />
      {stats && (
        <div className="flex justify-between mt-2 text-xs text-gray-400">
          <span>Invested: {formatTokenAmount(stats.totalIn, 6)} USDC</span>
          <span>Received: {formatTokenAmount(stats.totalOut, 18)} WETH</span>
        </div>
      )}
    </div>
  )
}
