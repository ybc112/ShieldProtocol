'use client'

import Link from 'next/link'
import { useStrategy } from '@/hooks'
import { Card, CardContent, Badge, Progress } from '@/components/ui'
import { getTokenByAddress, getStatusLabel, StrategyStatus } from '@/types'
import { formatTokenAmount } from '@/lib/utils'
import { ArrowRight, ChevronRight } from 'lucide-react'

interface StrategyListProps {
  strategyIds: `0x${string}`[] | undefined
  isLoading: boolean
}

export function StrategyList({ strategyIds, isLoading }: StrategyListProps) {
  if (isLoading) {
    return (
      <div className="space-y-4">
        {[1, 2].map((i) => (
          <Card key={i} className="animate-pulse">
            <CardContent className="p-6">
              <div className="h-6 w-48 bg-gray-700 rounded mb-4" />
              <div className="h-4 w-full bg-gray-800 rounded mb-2" />
              <div className="h-2 w-full bg-gray-800 rounded" />
            </CardContent>
          </Card>
        ))}
      </div>
    )
  }

  if (!strategyIds || strategyIds.length === 0) {
    return (
      <Card>
        <CardContent className="p-8 text-center">
          <p className="text-gray-400 mb-4">No strategies found</p>
          <a
            href="/strategies/new"
            className="inline-flex items-center text-primary-400 hover:text-primary-300"
          >
            Create your first strategy
            <ArrowRight className="ml-2 h-4 w-4" />
          </a>
        </CardContent>
      </Card>
    )
  }

  return (
    <div className="space-y-4">
      {strategyIds.map((strategyId) => (
        <StrategyCard key={strategyId} strategyId={strategyId} />
      ))}
    </div>
  )
}

function StrategyCard({ strategyId }: { strategyId: `0x${string}` }) {
  const { strategy, isLoading } = useStrategy(strategyId)

  if (isLoading || !strategy) {
    return (
      <Card className="animate-pulse">
        <CardContent className="p-6">
          <div className="h-6 w-48 bg-gray-700 rounded mb-4" />
          <div className="h-4 w-full bg-gray-800 rounded" />
        </CardContent>
      </Card>
    )
  }

  const sourceToken = getTokenByAddress(strategy.sourceToken)
  const targetToken = getTokenByAddress(strategy.targetToken)
  const progress =
    (Number(strategy.executionsCompleted) / Number(strategy.totalExecutions)) *
    100
  const isActive = strategy.status === StrategyStatus.Active

  const statusVariant =
    strategy.status === StrategyStatus.Active
      ? 'success'
      : strategy.status === StrategyStatus.Paused
      ? 'warning'
      : strategy.status === StrategyStatus.Completed
      ? 'secondary'
      : 'destructive'

  return (
    <Link href={`/strategies/${strategyId}`}>
      <Card className={`hover:border-primary-600/50 transition-colors cursor-pointer ${!isActive ? 'opacity-75' : ''}`}>
        <CardContent className="p-6">
          <div className="flex items-start justify-between mb-4">
            <div>
              <div className="flex items-center space-x-3 mb-1">
                <h3 className="text-lg font-semibold">
                  {sourceToken?.symbol || 'Unknown'} → {targetToken?.symbol || 'Unknown'}
                </h3>
                <Badge variant={statusVariant}>{getStatusLabel(strategy.status)}</Badge>
              </div>
              <p className="text-sm text-gray-400">
                {formatTokenAmount(strategy.amountPerExecution, sourceToken?.decimals || 6)}{' '}
                {sourceToken?.symbol} per execution
              </p>
            </div>

            <ChevronRight className="h-5 w-5 text-gray-500" />
          </div>

          <div className="space-y-2">
            <div className="flex justify-between text-sm">
              <span className="text-gray-400">Progress</span>
              <span className="text-gray-300">
                {strategy.executionsCompleted.toString()} / {strategy.totalExecutions.toString()} executions
              </span>
            </div>
            <Progress value={progress} />
          </div>

          <div className="grid grid-cols-2 gap-4 mt-4 pt-4 border-t border-gray-800">
            <div>
              <p className="text-xs text-gray-500">Interval</p>
              <p className="text-sm text-gray-300">
                {formatInterval(Number(strategy.intervalSeconds))}
              </p>
            </div>
            <div>
              <p className="text-xs text-gray-500">Next Execution</p>
              <p className="text-sm text-gray-300">
                {strategy.status === StrategyStatus.Active
                  ? formatNextExecution(Number(strategy.nextExecutionTime))
                  : '-'}
              </p>
            </div>
          </div>
        </CardContent>
      </Card>
    </Link>
  )
}

function formatInterval(seconds: number): string {
  if (seconds < 3600) return `${Math.floor(seconds / 60)} minutes`
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} hours`
  return `${Math.floor(seconds / 86400)} days`
}

function formatNextExecution(timestamp: number): string {
  const now = Math.floor(Date.now() / 1000)
  const diff = timestamp - now

  if (diff <= 0) return 'Ready'
  if (diff < 3600) return `${Math.floor(diff / 60)}m`
  if (diff < 86400) return `${Math.floor(diff / 3600)}h`
  return `${Math.floor(diff / 86400)}d`
}
