'use client'

import { useState, useEffect } from 'react'
import { useAccount } from 'wagmi'
import { useRouter } from 'next/navigation'
import { ArrowRight, TrendingUp, Info } from 'lucide-react'
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
import { useCreateStrategy, useShieldConfig, useDCAExecutorAllowance } from '@/hooks'
import { SUPPORTED_TOKENS } from '@/types'
import { parseUnits } from 'viem'

const INTERVALS = [
  { label: 'Hourly', value: 3600 },
  { label: 'Daily', value: 86400 },
  { label: 'Weekly', value: 604800 },
  { label: 'Monthly', value: 2592000 },
]

export default function CreateStrategyPage() {
  const router = useRouter()
  const { isConnected } = useAccount()
  const { config } = useShieldConfig()
  const { createStrategy, isPending, isSuccess, error } = useCreateStrategy()

  // Form state
  const [sourceToken, setSourceToken] = useState(SUPPORTED_TOKENS[1].address) // USDC
  const [targetToken, setTargetToken] = useState(SUPPORTED_TOKENS[0].address) // WETH
  const [amount, setAmount] = useState('20')
  const [interval, setInterval] = useState(86400) // Daily
  const [executions, setExecutions] = useState('30')

  // Token approval state
  const sourceTokenInfo = SUPPORTED_TOKENS.find((t) => t.address === sourceToken)
  const targetTokenInfo = SUPPORTED_TOKENS.find((t) => t.address === targetToken)
  const totalAmount = parseFloat(amount || '0') * parseInt(executions || '0')
  const requiredAmount = sourceTokenInfo
    ? parseUnits(totalAmount.toString(), sourceTokenInfo.decimals)
    : 0n

  const { allowance, refetch: refetchAllowance } = useDCAExecutorAllowance(
    sourceToken as `0x${string}`
  )
  const hasApproval = allowance !== undefined && allowance >= requiredAmount

  // Redirect after success
  useEffect(() => {
    if (isSuccess) {
      router.push('/strategies')
    }
  }, [isSuccess, router])

  if (!isConnected) {
    return <ConnectPrompt />
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    if (!hasApproval) {
      return
    }

    try {
      const decimals = sourceTokenInfo?.decimals || 6

      await createStrategy({
        sourceToken: sourceToken as `0x${string}`,
        targetToken: targetToken as `0x${string}`,
        amountPerExecution: parseUnits(amount, decimals),
        minAmountOut: 0n,
        intervalSeconds: BigInt(interval),
        totalExecutions: BigInt(executions),
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
        <h1 className="text-3xl font-bold">Create DCA Strategy</h1>
        <p className="text-gray-400 mt-1">
          Set up an automated dollar-cost averaging strategy
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
                    Activate now →
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
              <TrendingUp className="h-6 w-6 text-primary-400" />
            </div>
            <div>
              <CardTitle>DCA Configuration</CardTitle>
              <CardDescription>
                Configure your automated investment strategy
              </CardDescription>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-6">
            {/* Token Selection */}
            <div className="grid gap-4 md:grid-cols-2">
              <div>
                <label className="block text-sm font-medium text-gray-300 mb-1.5">
                  From Token
                </label>
                <select
                  value={sourceToken}
                  onChange={(e) => setSourceToken(e.target.value)}
                  className="w-full h-10 px-3 rounded-lg border border-gray-700 bg-gray-800 text-gray-100 focus:ring-2 focus:ring-primary-500"
                >
                  {SUPPORTED_TOKENS.map((token) => (
                    <option key={token.address} value={token.address}>
                      {token.symbol}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-300 mb-1.5">
                  To Token
                </label>
                <select
                  value={targetToken}
                  onChange={(e) => setTargetToken(e.target.value)}
                  className="w-full h-10 px-3 rounded-lg border border-gray-700 bg-gray-800 text-gray-100 focus:ring-2 focus:ring-primary-500"
                >
                  {SUPPORTED_TOKENS.filter((t) => t.address !== sourceToken).map(
                    (token) => (
                      <option key={token.address} value={token.address}>
                        {token.symbol}
                      </option>
                    )
                  )}
                </select>
              </div>
            </div>

            {/* Amount */}
            <Input
              label={`Amount per execution (${sourceTokenInfo?.symbol})`}
              type="number"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="20"
            />

            {/* Interval */}
            <div>
              <label className="block text-sm font-medium text-gray-300 mb-2">
                Execution Frequency
              </label>
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

            {/* Total Executions */}
            <Input
              label="Total Executions"
              type="number"
              value={executions}
              onChange={(e) => setExecutions(e.target.value)}
              placeholder="30"
            />

            {/* Summary */}
            <div className="p-4 rounded-lg bg-gray-800/50 space-y-3">
              <h4 className="text-sm font-medium text-gray-300">Strategy Summary</h4>
              <div className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-gray-400">Total Investment</span>
                  <span className="text-gray-100">
                    {totalAmount.toLocaleString()} {sourceTokenInfo?.symbol}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-400">Duration</span>
                  <span className="text-gray-100">
                    {Math.ceil((interval * parseInt(executions || '0')) / 86400)} days
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-400">Strategy</span>
                  <span className="text-gray-100">
                    {sourceTokenInfo?.symbol} → {targetTokenInfo?.symbol}
                  </span>
                </div>
              </div>
            </div>

            {/* Token Approval */}
            {sourceTokenInfo && totalAmount > 0 && (
              <TokenApproval
                token={sourceTokenInfo}
                requiredAmount={requiredAmount}
                onApprovalComplete={() => refetchAllowance()}
              />
            )}

            {error && (
              <div className="p-3 rounded-lg bg-red-600/10 border border-red-600/30 text-sm text-red-400">
                {error.message}
              </div>
            )}

            <Button
              type="submit"
              loading={isPending}
              disabled={!config?.isActive || !hasApproval || totalAmount <= 0}
              className="w-full"
            >
              Create Strategy
              <ArrowRight className="ml-2 h-4 w-4" />
            </Button>

            {!hasApproval && totalAmount > 0 && (
              <p className="text-xs text-yellow-500 text-center">
                Please approve {sourceTokenInfo?.symbol} spending above before creating the strategy
              </p>
            )}
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
