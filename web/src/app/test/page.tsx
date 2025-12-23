'use client'

import { useState } from 'react'
import { useAccount } from 'wagmi'
import { Play, AlertCircle, CheckCircle, Clock, RefreshCw, Zap } from 'lucide-react'
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
  Button,
  Badge,
} from '@/components/ui'
import { ConnectPrompt } from '@/components/dashboard/ConnectPrompt'
import {
  useUserStrategies,
  useStrategy,
  useExecuteDCA,
  useCanExecute,
  useShieldConfig,
} from '@/hooks'
import { getTokenByAddress, getStatusLabel, StrategyStatus } from '@/types'
import { formatTokenAmount } from '@/lib/utils'

export default function TestPage() {
  const { isConnected } = useAccount()
  const { strategyIds, isLoading: isLoadingStrategies, refetch: refetchStrategies } = useUserStrategies()
  const { config } = useShieldConfig()

  if (!isConnected) {
    return <ConnectPrompt />
  }

  return (
    <div className="space-y-8">
      {/* Page Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold flex items-center gap-3">
            <Zap className="h-8 w-8 text-yellow-500" />
            DCA Test Console
          </h1>
          <p className="text-gray-400 mt-1">
            Manually test DCA strategy execution
          </p>
        </div>
        <Button variant="outline" onClick={() => refetchStrategies()}>
          <RefreshCw className="h-4 w-4 mr-2" />
          Refresh
        </Button>
      </div>

      {/* Shield Status */}
      <Card className={config?.isActive ? 'border-green-500/30' : 'border-yellow-500/30'}>
        <CardContent className="p-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-3">
              <div className={`p-2 rounded-lg ${config?.isActive ? 'bg-green-600/20' : 'bg-yellow-600/20'}`}>
                {config?.isActive ? (
                  <CheckCircle className="h-5 w-5 text-green-500" />
                ) : (
                  <AlertCircle className="h-5 w-5 text-yellow-500" />
                )}
              </div>
              <div>
                <p className="font-medium">Shield Status</p>
                <p className="text-sm text-gray-400">
                  {config?.isActive ? 'Active - Ready to execute' : 'Inactive - Activate Shield first'}
                </p>
              </div>
            </div>
            <Badge variant={config?.isActive ? 'success' : 'warning'}>
              {config?.isActive ? 'Active' : 'Inactive'}
            </Badge>
          </div>
          {config?.isActive && (
            <div className="mt-4 grid grid-cols-2 gap-4 text-sm">
              <div className="p-3 rounded-lg bg-gray-800/50">
                <p className="text-gray-400">Daily Limit</p>
                <p className="font-medium">{formatTokenAmount(config.dailySpendLimit, 6)} USDC</p>
              </div>
              <div className="p-3 rounded-lg bg-gray-800/50">
                <p className="text-gray-400">Spent Today</p>
                <p className="font-medium">{formatTokenAmount(config.spentToday, 6)} USDC</p>
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Strategies List */}
      <Card>
        <CardHeader>
          <CardTitle>Your Strategies</CardTitle>
          <CardDescription>
            Click "Execute" to manually trigger a DCA execution
          </CardDescription>
        </CardHeader>
        <CardContent>
          {isLoadingStrategies ? (
            <div className="flex items-center justify-center py-8">
              <RefreshCw className="h-6 w-6 animate-spin text-primary-400" />
            </div>
          ) : !strategyIds || strategyIds.length === 0 ? (
            <div className="text-center py-8">
              <p className="text-gray-400">No strategies found</p>
              <a href="/strategies/new" className="text-primary-400 hover:text-primary-300 text-sm">
                Create your first strategy
              </a>
            </div>
          ) : (
            <div className="space-y-4">
              {strategyIds.map((strategyId) => (
                <StrategyTestCard key={strategyId} strategyId={strategyId} />
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Instructions */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">How to Test DCA Execution</CardTitle>
        </CardHeader>
        <CardContent className="text-sm text-gray-400 space-y-2">
          <p>1. Make sure Shield is activated with sufficient daily limit</p>
          <p>2. Create a DCA strategy (or use an existing one)</p>
          <p>3. Ensure you have approved enough tokens to the DCAExecutor contract</p>
          <p>4. Click "Execute" button on a strategy when it shows "Ready to execute"</p>
          <p>5. Confirm the transaction in MetaMask</p>
          <p className="text-yellow-400 mt-4">
            Note: Execution will fail if the strategy is not due yet, paused, or if you exceed your daily limit.
          </p>
        </CardContent>
      </Card>
    </div>
  )
}

function StrategyTestCard({ strategyId }: { strategyId: `0x${string}` }) {
  const { strategy, isLoading, refetch } = useStrategy(strategyId)
  const { canExecute, reason, refetch: refetchCanExecute } = useCanExecute(strategyId)
  const { executeDCA, isPending, isConfirming, isSuccess, error, hash } = useExecuteDCA()
  const [executionResult, setExecutionResult] = useState<string | null>(null)

  if (isLoading || !strategy) {
    return (
      <div className="p-4 rounded-lg bg-gray-800/50 animate-pulse">
        <div className="h-6 w-48 bg-gray-700 rounded mb-2" />
        <div className="h-4 w-32 bg-gray-700 rounded" />
      </div>
    )
  }

  const sourceToken = getTokenByAddress(strategy.sourceToken)
  const targetToken = getTokenByAddress(strategy.targetToken)
  const isActive = strategy.status === StrategyStatus.Active

  const handleExecute = async () => {
    setExecutionResult(null)
    try {
      await executeDCA(strategyId)
    } catch (err: any) {
      setExecutionResult(`Error: ${err.message}`)
    }
  }

  const handleRefresh = () => {
    refetch()
    refetchCanExecute()
  }

  const getTimeUntilNext = () => {
    const now = Math.floor(Date.now() / 1000)
    const next = Number(strategy.nextExecutionTime)
    const diff = next - now

    if (diff <= 0) return 'Ready'
    if (diff < 60) return `${diff}s`
    if (diff < 3600) return `${Math.floor(diff / 60)}m`
    if (diff < 86400) return `${Math.floor(diff / 3600)}h`
    return `${Math.floor(diff / 86400)}d`
  }

  return (
    <div className={`p-4 rounded-lg border ${isActive ? 'bg-gray-800/50 border-gray-700' : 'bg-gray-900/50 border-gray-800 opacity-60'}`}>
      <div className="flex items-start justify-between">
        <div className="space-y-2">
          {/* Strategy Info */}
          <div className="flex items-center space-x-3">
            <h3 className="text-lg font-semibold">
              {sourceToken?.symbol} → {targetToken?.symbol}
            </h3>
            <Badge variant={isActive ? 'success' : 'secondary'}>
              {getStatusLabel(strategy.status)}
            </Badge>
          </div>

          {/* Details */}
          <div className="text-sm text-gray-400 space-y-1">
            <p>
              Amount: {formatTokenAmount(strategy.amountPerExecution, sourceToken?.decimals || 6)} {sourceToken?.symbol}
            </p>
            <p>
              Progress: {Number(strategy.executionsCompleted)} / {Number(strategy.totalExecutions)} executions
            </p>
            <p className="font-mono text-xs text-gray-500">
              ID: {strategyId.slice(0, 10)}...{strategyId.slice(-8)}
            </p>
          </div>

          {/* Next Execution Time */}
          <div className="flex items-center space-x-2 text-sm">
            <Clock className="h-4 w-4 text-gray-500" />
            <span className={canExecute ? 'text-green-400' : 'text-gray-400'}>
              Next: {getTimeUntilNext()}
            </span>
            {canExecute && (
              <Badge variant="success" className="text-xs">Ready to execute</Badge>
            )}
          </div>

          {/* Can Execute Status */}
          {!canExecute && reason && (
            <p className="text-xs text-yellow-400">
              Cannot execute: {reason}
            </p>
          )}
        </div>

        {/* Action Buttons */}
        <div className="flex flex-col space-y-2">
          <Button
            onClick={handleExecute}
            disabled={!isActive || isPending || isConfirming}
            loading={isPending || isConfirming}
            className="min-w-[120px]"
          >
            <Play className="h-4 w-4 mr-2" />
            {isPending ? 'Signing...' : isConfirming ? 'Confirming...' : 'Execute'}
          </Button>
          <Button variant="outline" size="sm" onClick={handleRefresh}>
            <RefreshCw className="h-3 w-3 mr-1" />
            Refresh
          </Button>
        </div>
      </div>

      {/* Transaction Status */}
      {(hash || isSuccess || error) && (
        <div className="mt-4 pt-4 border-t border-gray-700">
          {isSuccess && (
            <div className="flex items-center space-x-2 text-green-400">
              <CheckCircle className="h-4 w-4" />
              <span className="text-sm">Execution successful!</span>
            </div>
          )}
          {hash && (
            <p className="text-xs text-gray-500 mt-1">
              Tx: <a
                href={`https://sepolia.etherscan.io/tx/${hash}`}
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary-400 hover:text-primary-300"
              >
                {hash.slice(0, 10)}...{hash.slice(-8)}
              </a>
            </p>
          )}
          {error && (
            <div className="flex items-start space-x-2 text-red-400">
              <AlertCircle className="h-4 w-4 mt-0.5" />
              <span className="text-sm">{error.message}</span>
            </div>
          )}
        </div>
      )}
    </div>
  )
}
