'use client'

import { useState, useEffect } from 'react'
import { useAccount } from 'wagmi'
import { useRouter } from 'next/navigation'
import { ArrowRight, ShieldAlert, Info } from 'lucide-react'
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
import { useCreateStopLossStrategy, useShieldConfig } from '@/hooks'
import { SUPPORTED_TOKENS, StopLossType } from '@/types'
import { parseUnits } from 'viem'

const STOP_LOSS_TYPES = [
  {
    type: StopLossType.FixedPrice,
    label: 'Fixed Price',
    description: 'Trigger when price falls to a specific value'
  },
  {
    type: StopLossType.Percentage,
    label: 'Percentage Drop',
    description: 'Trigger when price drops by a percentage'
  },
  {
    type: StopLossType.TrailingStop,
    label: 'Trailing Stop',
    description: 'Follow price up, trigger on percentage drop from high'
  },
]

export default function CreateStopLossPage() {
  const router = useRouter()
  const { isConnected } = useAccount()
  const { config } = useShieldConfig()
  const { createStrategy, isPending, isSuccess, error } = useCreateStopLossStrategy()

  // Form state
  const [tokenToSell, setTokenToSell] = useState(SUPPORTED_TOKENS[0].address) // WETH
  const [tokenToReceive, setTokenToReceive] = useState(SUPPORTED_TOKENS[1].address) // USDC
  const [amount, setAmount] = useState('0.1')
  const [stopLossType, setStopLossType] = useState<StopLossType>(StopLossType.Percentage)
  const [triggerValue, setTriggerValue] = useState('10') // 10% drop or fixed price
  const [trailingDistance, setTrailingDistance] = useState('5') // 5% trailing
  const [slippage, setSlippage] = useState('1') // 1% slippage

  // Token info
  const sellTokenInfo = SUPPORTED_TOKENS.find((t) => t.address === tokenToSell)
  const receiveTokenInfo = SUPPORTED_TOKENS.find((t) => t.address === tokenToReceive)

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

    try {
      const decimals = sellTokenInfo?.decimals || 18
      const amountBigInt = parseUnits(amount, decimals)

      // Calculate trigger value based on type
      let triggerValueBigInt: bigint
      if (stopLossType === StopLossType.FixedPrice) {
        // Fixed price in USDC (6 decimals)
        triggerValueBigInt = parseUnits(triggerValue, 6)
      } else {
        // Percentage in basis points (100 = 1%)
        triggerValueBigInt = BigInt(Math.floor(parseFloat(triggerValue) * 100))
      }

      // Trailing distance in basis points
      const trailingDistanceBigInt = BigInt(Math.floor(parseFloat(trailingDistance) * 100))

      // Minimum amount out (accounting for slippage)
      const slippageBps = parseFloat(slippage) * 100
      const minAmountOutBigInt = 0n // In real implementation, calculate based on current price

      await createStrategy({
        tokenToSell: tokenToSell as `0x${string}`,
        tokenToReceive: tokenToReceive as `0x${string}`,
        amount: amountBigInt,
        stopLossType,
        triggerValue: triggerValueBigInt,
        trailingDistance: stopLossType === StopLossType.TrailingStop ? trailingDistanceBigInt : 0n,
        minAmountOut: minAmountOutBigInt,
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
        <h1 className="text-3xl font-bold">Create Stop-Loss Strategy</h1>
        <p className="text-gray-400 mt-1">
          Protect your assets with automatic sell orders
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
            <div className="p-3 rounded-lg bg-red-600/20">
              <ShieldAlert className="h-6 w-6 text-red-400" />
            </div>
            <div>
              <CardTitle>Stop-Loss Configuration</CardTitle>
              <CardDescription>
                Set up automatic sell protection
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
                  Token to Sell
                </label>
                <select
                  value={tokenToSell}
                  onChange={(e) => setTokenToSell(e.target.value)}
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
                  Receive Token
                </label>
                <select
                  value={tokenToReceive}
                  onChange={(e) => setTokenToReceive(e.target.value)}
                  className="w-full h-10 px-3 rounded-lg border border-gray-700 bg-gray-800 text-gray-100 focus:ring-2 focus:ring-primary-500"
                >
                  {SUPPORTED_TOKENS.filter((t) => t.address !== tokenToSell).map((token) => (
                    <option key={token.address} value={token.address}>
                      {token.symbol}
                    </option>
                  ))}
                </select>
              </div>
            </div>

            {/* Amount */}
            <Input
              label={`Amount to Protect (${sellTokenInfo?.symbol})`}
              type="number"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0.1"
            />

            {/* Stop-Loss Type */}
            <div>
              <label className="block text-sm font-medium text-gray-300 mb-2">
                Stop-Loss Type
              </label>
              <div className="space-y-2">
                {STOP_LOSS_TYPES.map((type) => (
                  <button
                    key={type.type}
                    type="button"
                    onClick={() => setStopLossType(type.type)}
                    className={`w-full p-4 rounded-lg text-left transition-colors border ${
                      stopLossType === type.type
                        ? 'border-primary-500 bg-primary-600/10'
                        : 'border-gray-700 bg-gray-800/50 hover:border-gray-600'
                    }`}
                  >
                    <div className="flex items-center space-x-2">
                      <div className={`w-3 h-3 rounded-full border-2 ${
                        stopLossType === type.type
                          ? 'border-primary-500 bg-primary-500'
                          : 'border-gray-500'
                      }`} />
                      <span className="font-medium text-gray-100">{type.label}</span>
                    </div>
                    <p className="text-xs text-gray-400 mt-1 ml-5">{type.description}</p>
                  </button>
                ))}
              </div>
            </div>

            {/* Trigger Value */}
            {stopLossType === StopLossType.FixedPrice ? (
              <Input
                label={`Trigger Price (${receiveTokenInfo?.symbol})`}
                type="number"
                value={triggerValue}
                onChange={(e) => setTriggerValue(e.target.value)}
                placeholder="2500"
              />
            ) : (
              <div>
                <label className="block text-sm font-medium text-gray-300 mb-1.5">
                  Trigger Drop Percentage
                </label>
                <div className="relative">
                  <input
                    type="number"
                    value={triggerValue}
                    onChange={(e) => setTriggerValue(e.target.value)}
                    className="w-full h-10 px-3 pr-8 rounded-lg border border-gray-700 bg-gray-800 text-gray-100 focus:ring-2 focus:ring-primary-500"
                    placeholder="10"
                  />
                  <span className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400">%</span>
                </div>
                <p className="text-xs text-gray-500 mt-1">
                  {stopLossType === StopLossType.Percentage
                    ? 'Sell when price drops by this percentage from entry'
                    : 'Sell when price drops by this percentage from highest observed'
                  }
                </p>
              </div>
            )}

            {/* Trailing Distance (only for trailing stop) */}
            {stopLossType === StopLossType.TrailingStop && (
              <div>
                <label className="block text-sm font-medium text-gray-300 mb-1.5">
                  Trailing Distance
                </label>
                <div className="relative">
                  <input
                    type="number"
                    value={trailingDistance}
                    onChange={(e) => setTrailingDistance(e.target.value)}
                    className="w-full h-10 px-3 pr-8 rounded-lg border border-gray-700 bg-gray-800 text-gray-100 focus:ring-2 focus:ring-primary-500"
                    placeholder="5"
                  />
                  <span className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400">%</span>
                </div>
                <p className="text-xs text-gray-500 mt-1">
                  Distance the stop follows the price upward
                </p>
              </div>
            )}

            {/* Slippage */}
            <div>
              <label className="block text-sm font-medium text-gray-300 mb-1.5">
                Max Slippage
              </label>
              <div className="flex gap-2">
                {['0.5', '1', '2', '3'].map((value) => (
                  <button
                    key={value}
                    type="button"
                    onClick={() => setSlippage(value)}
                    className={`flex-1 px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
                      slippage === value
                        ? 'bg-primary-600 text-white'
                        : 'bg-gray-800 text-gray-400 hover:bg-gray-700'
                    }`}
                  >
                    {value}%
                  </button>
                ))}
              </div>
            </div>

            {/* Summary */}
            <div className="p-4 rounded-lg bg-gray-800/50 space-y-3">
              <h4 className="text-sm font-medium text-gray-300">Strategy Summary</h4>
              <div className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-gray-400">Protected Amount</span>
                  <span className="text-gray-100">
                    {amount} {sellTokenInfo?.symbol}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-400">Stop-Loss Type</span>
                  <span className="text-gray-100">
                    {STOP_LOSS_TYPES.find((t) => t.type === stopLossType)?.label}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-400">Trigger</span>
                  <span className="text-gray-100">
                    {stopLossType === StopLossType.FixedPrice
                      ? `$${triggerValue}`
                      : `${triggerValue}% drop`
                    }
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-gray-400">Receive</span>
                  <span className="text-gray-100">{receiveTokenInfo?.symbol}</span>
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
              disabled={!config?.isActive || parseFloat(amount) <= 0}
              className="w-full"
            >
              Create Stop-Loss Strategy
              <ArrowRight className="ml-2 h-4 w-4" />
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
