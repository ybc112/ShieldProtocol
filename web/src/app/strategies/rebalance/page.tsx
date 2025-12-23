'use client'

import { useState, useEffect } from 'react'
import { useAccount } from 'wagmi'
import { useRouter } from 'next/navigation'
import { ArrowRight, RefreshCw, Info, Plus, Trash2 } from 'lucide-react'
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
  Button,
  Input,
} from '@/components/ui'
import { ConnectPrompt, TokenApproval } from '@/components/dashboard'
import { useCreateRebalanceStrategy, useShieldConfig } from '@/hooks'
import { SUPPORTED_TOKENS } from '@/types'

const INTERVALS = [
  { label: '1 Hour', value: 3600 },
  { label: '6 Hours', value: 21600 },
  { label: '1 Day', value: 86400 },
  { label: '1 Week', value: 604800 },
]

const THRESHOLDS = [
  { label: '1%', value: 100 },
  { label: '3%', value: 300 },
  { label: '5%', value: 500 },
  { label: '10%', value: 1000 },
]

interface Allocation {
  token: string
  weight: number
}

export default function CreateRebalancePage() {
  const router = useRouter()
  const { isConnected } = useAccount()
  const { config } = useShieldConfig()
  const { createStrategy, isPending, isSuccess, error } = useCreateRebalanceStrategy()

  // Form state
  const [allocations, setAllocations] = useState<Allocation[]>([
    { token: SUPPORTED_TOKENS[0].address, weight: 50 },
    { token: SUPPORTED_TOKENS[1].address, weight: 50 },
  ])
  const [threshold, setThreshold] = useState(500) // 5%
  const [interval, setInterval] = useState(86400) // 1 day

  // Calculate total weight
  const totalWeight = allocations.reduce((sum, a) => sum + a.weight, 0)
  const isValidWeight = totalWeight === 100

  // Redirect after success
  useEffect(() => {
    if (isSuccess) {
      router.push('/strategies')
    }
  }, [isSuccess, router])

  if (!isConnected) {
    return <ConnectPrompt />
  }

  const addAllocation = () => {
    const availableTokens = SUPPORTED_TOKENS.filter(
      (t) => !allocations.some((a) => a.token === t.address)
    )
    if (availableTokens.length > 0) {
      setAllocations([
        ...allocations,
        { token: availableTokens[0].address, weight: 0 },
      ])
    }
  }

  const removeAllocation = (index: number) => {
    if (allocations.length > 2) {
      setAllocations(allocations.filter((_, i) => i !== index))
    }
  }

  const updateAllocation = (index: number, field: 'token' | 'weight', value: string | number) => {
    const updated = [...allocations]
    if (field === 'token') {
      updated[index].token = value as string
    } else {
      updated[index].weight = Math.max(0, Math.min(100, value as number))
    }
    setAllocations(updated)
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!isValidWeight) {
      return
    }

    try {
      await createStrategy({
        tokens: allocations.map((a) => a.token as `0x${string}`),
        targetWeights: allocations.map((a) => BigInt(a.weight * 100)), // Convert to basis points
        rebalanceThreshold: BigInt(threshold),
        minRebalanceInterval: BigInt(interval),
        poolFee: 3000, // 0.3%
      })
    } catch (err) {
      console.error('Failed to create strategy:', err)
    }
  }

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      {/* Page Header */}
      <div>
        <h1 className="text-3xl font-bold">Create Rebalance Strategy</h1>
        <p className="text-gray-400 mt-1">
          Set up automatic portfolio rebalancing
        </p>
      </div>

      {/* Shield Status Warning */}
      {!config?.isActive && (
        <Card className="border-yellow-500/50">
          <CardContent className="p-4">
            <div className="flex items-start space-x-3">
              <Info className="h-5 w-5 text-yellow-500 mt-0.5" />
              <div>
                <p className="text-sm text-yellow-200">
                  Shield is not activated
                </p>
                <p className="text-xs text-gray-400 mt-1">
                  You need to activate Shield before creating strategies.{' '}
                  <a href="/shield" className="text-primary-400 hover:text-primary-300">
                    Activate now
                  </a>
                </p>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Strategy Form */}
      <Card>
        <CardHeader>
          <div className="flex items-center space-x-3">
            <div className="p-3 rounded-lg bg-primary-600/20">
              <RefreshCw className="h-6 w-6 text-primary-400" />
            </div>
            <div>
              <CardTitle>Portfolio Allocation</CardTitle>
              <CardDescription>
                Define your target asset allocation
              </CardDescription>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-6">
            {/* Asset Allocations */}
            <div className="space-y-3">
              <div className="flex items-center justify-between">
                <label className="block text-sm font-medium text-gray-300">
                  Target Allocations
                </label>
                <span className={`text-sm ${isValidWeight ? 'text-green-400' : 'text-red-400'}`}>
                  Total: {totalWeight}%
                </span>
              </div>

              {allocations.map((allocation, index) => {
                const token = SUPPORTED_TOKENS.find((t) => t.address === allocation.token)
                return (
                  <div key={index} className="flex items-center space-x-3">
                    <select
                      value={allocation.token}
                      onChange={(e) => updateAllocation(index, 'token', e.target.value)}
                      className="flex-1 h-10 px-3 rounded-lg border border-gray-700 bg-gray-800 text-gray-100 focus:ring-2 focus:ring-primary-500"
                    >
                      {SUPPORTED_TOKENS.map((t) => (
                        <option
                          key={t.address}
                          value={t.address}
                          disabled={allocations.some((a, i) => i !== index && a.token === t.address)}
                        >
                          {t.symbol}
                        </option>
                      ))}
                    </select>
                    <div className="relative w-24">
                      <input
                        type="number"
                        value={allocation.weight}
                        onChange={(e) => updateAllocation(index, 'weight', parseInt(e.target.value) || 0)}
                        className="w-full h-10 px-3 pr-8 rounded-lg border border-gray-700 bg-gray-800 text-gray-100 focus:ring-2 focus:ring-primary-500"
                        min={0}
                        max={100}
                      />
                      <span className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400">%</span>
                    </div>
                    {allocations.length > 2 && (
                      <button
                        type="button"
                        onClick={() => removeAllocation(index)}
                        className="p-2 rounded-lg hover:bg-gray-700 text-gray-400 hover:text-red-500"
                      >
                        <Trash2 className="h-4 w-4" />
                      </button>
                    )}
                  </div>
                )
              })}

              {allocations.length < SUPPORTED_TOKENS.length && (
                <button
                  type="button"
                  onClick={addAllocation}
                  className="flex items-center space-x-2 text-sm text-primary-400 hover:text-primary-300"
                >
                  <Plus className="h-4 w-4" />
                  <span>Add Token</span>
                </button>
              )}
            </div>

            {/* Rebalance Threshold */}
            <div>
              <label className="block text-sm font-medium text-gray-300 mb-2">
                Rebalance Threshold
              </label>
              <p className="text-xs text-gray-500 mb-2">
                Rebalance when allocation drifts by this percentage
              </p>
              <div className="grid grid-cols-4 gap-2">
                {THRESHOLDS.map((t) => (
                  <button
                    key={t.value}
                    type="button"
                    onClick={() => setThreshold(t.value)}
                    className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                      threshold === t.value
                        ? 'bg-primary-600 text-white'
                        : 'bg-gray-800 text-gray-400 hover:bg-gray-700'
                    }`}
                  >
                    {t.label}
                  </button>
                ))}
              </div>
            </div>

            {/* Minimum Interval */}
            <div>
              <label className="block text-sm font-medium text-gray-300 mb-2">
                Minimum Rebalance Interval
              </label>
              <p className="text-xs text-gray-500 mb-2">
                Minimum time between rebalancing events
              </p>
              <div className="grid grid-cols-4 gap-2">
                {INTERVALS.map((int) => (
                  <button
                    key={int.value}
                    type="button"
                    onClick={() => setInterval(int.value)}
                    className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                      interval === int.value
                        ? 'bg-primary-600 text-white'
                        : 'bg-gray-800 text-gray-400 hover:bg-gray-700'
                    }`}
                  >
                    {int.label}
                  </button>
                ))}
              </div>
            </div>

            {/* Summary */}
            <div className="p-4 rounded-lg bg-gray-800/50 space-y-3">
              <h4 className="text-sm font-medium text-gray-300">Strategy Summary</h4>
              <div className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-gray-400">Portfolio Composition</span>
                  <span className="text-gray-100">
                    {allocations.map((a) => {
                      const token = SUPPORTED_TOKENS.find((t) => t.address === a.token)
                      return `${a.weight}% ${token?.symbol}`
                    }).join(' / ')}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-400">Rebalance Trigger</span>
                  <span className="text-gray-100">{threshold / 100}% drift</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-400">Min Interval</span>
                  <span className="text-gray-100">
                    {INTERVALS.find((i) => i.value === interval)?.label}
                  </span>
                </div>
              </div>
            </div>

            {error && (
              <div className="p-3 rounded-lg bg-red-600/10 border border-red-600/30 text-sm text-red-400">
                {error.message}
              </div>
            )}

            <Button
              type="submit"
              loading={isPending}
              disabled={!config?.isActive || !isValidWeight}
              className="w-full"
            >
              Create Rebalance Strategy
              <ArrowRight className="ml-2 h-4 w-4" />
            </Button>

            {!isValidWeight && (
              <p className="text-xs text-red-500 text-center">
                Total allocation must equal 100%
              </p>
            )}
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
