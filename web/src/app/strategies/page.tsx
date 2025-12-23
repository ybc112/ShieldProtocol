'use client'

import { useAccount } from 'wagmi'
import { Plus } from 'lucide-react'
import Link from 'next/link'
import { Button } from '@/components/ui'
import { StrategyList } from '@/components/dashboard/StrategyList'
import { ConnectPrompt } from '@/components/dashboard/ConnectPrompt'
import { useUserStrategies } from '@/hooks'

export default function StrategiesPage() {
  const { isConnected } = useAccount()
  const { strategyIds, isLoading } = useUserStrategies()

  if (!isConnected) {
    return <ConnectPrompt />
  }

  return (
    <div className="space-y-8">
      {/* Page Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold">My Strategies</h1>
          <p className="text-gray-400 mt-1">
            Manage your automated investment strategies
          </p>
        </div>
        <Link href="/strategies/new">
          <Button>
            <Plus className="mr-2 h-4 w-4" />
            Create Strategy
          </Button>
        </Link>
      </div>

      {/* Strategy List */}
      <StrategyList strategyIds={strategyIds} isLoading={isLoading} />
    </div>
  )
}
