'use client'

import { useAccount } from 'wagmi'
import { Shield, TrendingUp, Wallet, AlertTriangle } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle, Badge, Progress } from '@/components/ui'
import { useShieldConfig, useRemainingAllowance, useUserStrategies } from '@/hooks'
import { formatTokenAmount, shortenAddress } from '@/lib/utils'
import { StrategyList } from '@/components/dashboard/StrategyList'
import { ShieldStatusCard } from '@/components/dashboard/ShieldStatusCard'
import { ConnectPrompt } from '@/components/dashboard/ConnectPrompt'

export default function DashboardPage() {
  const { address, isConnected } = useAccount()
  const { config, isLoading: isLoadingConfig } = useShieldConfig()
  const { remainingAllowance } = useRemainingAllowance()
  const { strategyIds, isLoading: isLoadingStrategies } = useUserStrategies()

  if (!isConnected) {
    return <ConnectPrompt />
  }

  const activeStrategiesCount = strategyIds?.length || 0

  return (
    <div className="space-y-8">
      {/* Page Header */}
      <div>
        <h1 className="text-3xl font-bold">Dashboard</h1>
        <p className="text-gray-400 mt-1">
          Welcome back, {shortenAddress(address!)}
        </p>
      </div>

      {/* Stats Cards */}
      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-4">
        {/* Shield Status */}
        <ShieldStatusCard config={config} isLoading={isLoadingConfig} />

        {/* Active Strategies */}
        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-gray-400">
              Active Strategies
            </CardTitle>
            <TrendingUp className="h-4 w-4 text-green-500" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{activeStrategiesCount}</div>
            <p className="text-xs text-gray-500 mt-1">
              DCA strategies running
            </p>
          </CardContent>
        </Card>

        {/* Daily Remaining */}
        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-gray-400">
              Daily Remaining
            </CardTitle>
            <Wallet className="h-4 w-4 text-blue-500" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">
              {remainingAllowance
                ? formatTokenAmount(remainingAllowance, 6)
                : '0'}{' '}
              <span className="text-sm text-gray-400">USDC</span>
            </div>
            {config && config.isActive && (
              <Progress
                value={
                  Number(config.dailySpendLimit - (remainingAllowance || 0n))
                }
                max={Number(config.dailySpendLimit)}
                className="mt-2"
              />
            )}
          </CardContent>
        </Card>

        {/* Emergency Status */}
        <Card className={config?.emergencyMode ? 'border-red-500/50' : ''}>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-gray-400">
              Emergency Mode
            </CardTitle>
            <AlertTriangle
              className={`h-4 w-4 ${
                config?.emergencyMode ? 'text-red-500' : 'text-gray-500'
              }`}
            />
          </CardHeader>
          <CardContent>
            <Badge variant={config?.emergencyMode ? 'destructive' : 'secondary'}>
              {config?.emergencyMode ? 'ACTIVE' : 'Inactive'}
            </Badge>
            <p className="text-xs text-gray-500 mt-2">
              {config?.emergencyMode
                ? 'All operations frozen'
                : 'System operating normally'}
            </p>
          </CardContent>
        </Card>
      </div>

      {/* Limits Overview */}
      {config?.isActive && (
        <Card>
          <CardHeader>
            <CardTitle>Spending Limits</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="grid gap-6 md:grid-cols-2">
              <div>
                <p className="text-sm text-gray-400 mb-2">Daily Limit</p>
                <p className="text-xl font-semibold">
                  {formatTokenAmount(config.dailySpendLimit, 6)} USDC
                </p>
                <Progress
                  value={Number(config.spentToday)}
                  max={Number(config.dailySpendLimit)}
                  showLabel
                  className="mt-2"
                />
                <p className="text-xs text-gray-500 mt-1">
                  Spent today: {formatTokenAmount(config.spentToday, 6)} USDC
                </p>
              </div>
              <div>
                <p className="text-sm text-gray-400 mb-2">Single Transaction Limit</p>
                <p className="text-xl font-semibold">
                  {formatTokenAmount(config.singleTxLimit, 6)} USDC
                </p>
                <p className="text-xs text-gray-500 mt-2">
                  Maximum amount per transaction
                </p>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Strategies Section */}
      <div>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-xl font-semibold">My Strategies</h2>
          <a
            href="/strategies/new"
            className="text-sm text-primary-400 hover:text-primary-300"
          >
            Create New →
          </a>
        </div>
        <StrategyList
          strategyIds={strategyIds}
          isLoading={isLoadingStrategies}
        />
      </div>
    </div>
  )
}
