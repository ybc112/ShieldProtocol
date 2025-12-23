'use client'

import { useState } from 'react'
import { useAccount } from 'wagmi'
import { Plus, CreditCard, Users, ArrowRight, Calendar, Clock } from 'lucide-react'
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
  Button,
  Input,
  Badge,
} from '@/components/ui'
import { ConnectPrompt } from '@/components/dashboard/ConnectPrompt'
import { TokenApproval } from '@/components/dashboard/TokenApproval'
import {
  useSubscriberSubscriptions,
  useRecipientSubscriptions,
  useMonthlySubscriptionCost,
  useCreateSubscription,
  BillingPeriod,
  getBillingPeriodLabel,
} from '@/hooks/useSubscription'
import { useShieldConfig, useTokenAllowance } from '@/hooks'
import { SUPPORTED_TOKENS } from '@/types'
import { CONTRACT_ADDRESSES } from '@/lib/contracts'
import { parseUnits, formatUnits } from 'viem'
import { SubscriptionCard } from '@/components/subscribe/SubscriptionCard'

const BILLING_PERIODS = [
  { label: 'Daily', value: BillingPeriod.Daily },
  { label: 'Weekly', value: BillingPeriod.Weekly },
  { label: 'Monthly', value: BillingPeriod.Monthly },
  { label: 'Yearly', value: BillingPeriod.Yearly },
]

export default function SubscribePage() {
  const { isConnected } = useAccount()
  const { config } = useShieldConfig()
  const { subscriptionIds: mySubscriptions, isLoading: loadingMy, refetch: refetchMy } = useSubscriberSubscriptions()
  const { subscriptionIds: incomingSubscriptions, isLoading: loadingIncoming, refetch: refetchIncoming } = useRecipientSubscriptions()
  const { monthlyCost } = useMonthlySubscriptionCost()
  const { createSubscription, isPending, isSuccess, error, reset } = useCreateSubscription()

  // Form state
  const [showCreateForm, setShowCreateForm] = useState(false)
  const [recipient, setRecipient] = useState('')
  const [token, setToken] = useState(SUPPORTED_TOKENS[1].address) // USDC
  const [amount, setAmount] = useState('10')
  const [billingPeriod, setBillingPeriod] = useState(BillingPeriod.Monthly)
  const [maxPayments, setMaxPayments] = useState('12') // 12 months
  const [executeFirst, setExecuteFirst] = useState(true)

  const selectedToken = SUPPORTED_TOKENS.find(t => t.address === token)
  const totalAmount = parseFloat(amount || '0') * parseInt(maxPayments || '0')
  const requiredAmount = selectedToken
    ? parseUnits(amount || '0', selectedToken.decimals)
    : 0n

  const { allowance } = useTokenAllowance(
    token as `0x${string}`,
    CONTRACT_ADDRESSES.subscriptionManager
  )
  const hasApproval = allowance !== undefined && allowance >= requiredAmount

  if (!isConnected) {
    return <ConnectPrompt />
  }

  const handleCreateSubscription = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!recipient || !hasApproval) return

    try {
      await createSubscription({
        recipient: recipient as `0x${string}`,
        token: token as `0x${string}`,
        amount: parseUnits(amount, selectedToken?.decimals || 6),
        billingPeriod,
        maxPayments: BigInt(maxPayments || 0),
        executeFirstPayment: executeFirst,
      })

      if (isSuccess) {
        setShowCreateForm(false)
        setRecipient('')
        setAmount('10')
        refetchMy()
        reset()
      }
    } catch (err) {
      console.error('Failed to create subscription:', err)
    }
  }

  return (
    <div className="space-y-8">
      {/* Page Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold">Subscriptions</h1>
          <p className="text-gray-400 mt-1">
            Manage your Web3 subscriptions and recurring payments
          </p>
        </div>
        <Button onClick={() => setShowCreateForm(!showCreateForm)}>
          <Plus className="mr-2 h-4 w-4" />
          New Subscription
        </Button>
      </div>

      {/* Stats */}
      <div className="grid gap-6 md:grid-cols-3">
        <Card>
          <CardContent className="p-6">
            <div className="flex items-center space-x-3">
              <div className="p-2 rounded-lg bg-primary-600/20">
                <CreditCard className="h-5 w-5 text-primary-400" />
              </div>
              <div>
                <p className="text-sm text-gray-400">Monthly Cost</p>
                <p className="text-xl font-bold">
                  {monthlyCost ? formatUnits(monthlyCost, 6) : '0'} USDC
                </p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-6">
            <div className="flex items-center space-x-3">
              <div className="p-2 rounded-lg bg-blue-600/20">
                <Calendar className="h-5 w-5 text-blue-400" />
              </div>
              <div>
                <p className="text-sm text-gray-400">Active Subscriptions</p>
                <p className="text-xl font-bold">
                  {mySubscriptions?.length || 0}
                </p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardContent className="p-6">
            <div className="flex items-center space-x-3">
              <div className="p-2 rounded-lg bg-green-600/20">
                <Users className="h-5 w-5 text-green-400" />
              </div>
              <div>
                <p className="text-sm text-gray-400">Subscribers (Incoming)</p>
                <p className="text-xl font-bold">
                  {incomingSubscriptions?.length || 0}
                </p>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Create Subscription Form */}
      {showCreateForm && (
        <Card>
          <CardHeader>
            <CardTitle>Create New Subscription</CardTitle>
            <CardDescription>
              Set up recurring payments to a creator, service, or DAO
            </CardDescription>
          </CardHeader>
          <CardContent>
            <form onSubmit={handleCreateSubscription} className="space-y-6">
              {/* Recipient */}
              <Input
                label="Recipient Address"
                value={recipient}
                onChange={(e) => setRecipient(e.target.value)}
                placeholder="0x..."
              />

              {/* Token and Amount */}
              <div className="grid gap-4 md:grid-cols-2">
                <div>
                  <label className="block text-sm font-medium text-gray-300 mb-1.5">
                    Payment Token
                  </label>
                  <select
                    value={token}
                    onChange={(e) => setToken(e.target.value)}
                    className="w-full h-10 px-3 rounded-lg border border-gray-700 bg-gray-800 text-gray-100 focus:ring-2 focus:ring-primary-500"
                  >
                    {SUPPORTED_TOKENS.map((t) => (
                      <option key={t.address} value={t.address}>
                        {t.symbol}
                      </option>
                    ))}
                  </select>
                </div>
                <Input
                  label={`Amount per payment (${selectedToken?.symbol})`}
                  type="number"
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  placeholder="10"
                />
              </div>

              {/* Billing Period */}
              <div>
                <label className="block text-sm font-medium text-gray-300 mb-2">
                  Billing Period
                </label>
                <div className="grid grid-cols-4 gap-2">
                  {BILLING_PERIODS.map((period) => (
                    <button
                      key={period.value}
                      type="button"
                      onClick={() => setBillingPeriod(period.value)}
                      className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                        billingPeriod === period.value
                          ? 'bg-primary-600 text-white'
                          : 'bg-gray-800 text-gray-400 hover:bg-gray-700'
                      }`}
                    >
                      {period.label}
                    </button>
                  ))}
                </div>
              </div>

              {/* Max Payments */}
              <Input
                label="Number of Payments (0 = unlimited)"
                type="number"
                value={maxPayments}
                onChange={(e) => setMaxPayments(e.target.value)}
                placeholder="12"
              />

              {/* Execute First */}
              <div className="flex items-center space-x-2">
                <input
                  type="checkbox"
                  id="executeFirst"
                  checked={executeFirst}
                  onChange={(e) => setExecuteFirst(e.target.checked)}
                  className="w-4 h-4 rounded border-gray-700 bg-gray-800 text-primary-600 focus:ring-primary-500"
                />
                <label htmlFor="executeFirst" className="text-sm text-gray-300">
                  Execute first payment immediately
                </label>
              </div>

              {/* Summary */}
              <div className="p-4 rounded-lg bg-gray-800/50 space-y-2">
                <h4 className="text-sm font-medium text-gray-300">Subscription Summary</h4>
                <div className="grid grid-cols-2 gap-2 text-sm">
                  <span className="text-gray-400">Per Payment:</span>
                  <span>{amount} {selectedToken?.symbol}</span>
                  <span className="text-gray-400">Frequency:</span>
                  <span>{getBillingPeriodLabel(billingPeriod)}</span>
                  <span className="text-gray-400">Total Payments:</span>
                  <span>{maxPayments === '0' ? 'Unlimited' : maxPayments}</span>
                  {maxPayments !== '0' && (
                    <>
                      <span className="text-gray-400">Total Amount:</span>
                      <span>{totalAmount} {selectedToken?.symbol}</span>
                    </>
                  )}
                </div>
              </div>

              {/* Token Approval */}
              {selectedToken && parseFloat(amount) > 0 && (
                <TokenApproval
                  token={selectedToken}
                  requiredAmount={requiredAmount}
                  spender={CONTRACT_ADDRESSES.subscriptionManager}
                />
              )}

              {/* Shield Warning */}
              {!config?.isActive && (
                <div className="p-3 rounded-lg bg-yellow-600/10 border border-yellow-600/30 text-sm text-yellow-400">
                  Shield must be activated before creating subscriptions.
                  <a href="/shield" className="ml-1 underline">Activate now</a>
                </div>
              )}

              {error && (
                <div className="p-3 rounded-lg bg-red-600/10 border border-red-600/30 text-sm text-red-400">
                  {error.message}
                </div>
              )}

              <div className="flex space-x-3">
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => setShowCreateForm(false)}
                >
                  Cancel
                </Button>
                <Button
                  type="submit"
                  loading={isPending}
                  disabled={!config?.isActive || !hasApproval || !recipient}
                  className="flex-1"
                >
                  Create Subscription
                  <ArrowRight className="ml-2 h-4 w-4" />
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      )}

      {/* My Subscriptions */}
      <div>
        <h2 className="text-xl font-semibold mb-4">My Subscriptions</h2>
        {loadingMy ? (
          <Card>
            <CardContent className="p-8 text-center">
              <Clock className="h-8 w-8 animate-spin text-gray-400 mx-auto" />
            </CardContent>
          </Card>
        ) : mySubscriptions && mySubscriptions.length > 0 ? (
          <div className="grid gap-4 md:grid-cols-2">
            {mySubscriptions.map((id) => (
              <SubscriptionCard
                key={id}
                subscriptionId={id}
                onUpdate={() => refetchMy()}
              />
            ))}
          </div>
        ) : (
          <Card>
            <CardContent className="p-8 text-center">
              <CreditCard className="h-12 w-12 text-gray-600 mx-auto mb-4" />
              <p className="text-gray-400">No active subscriptions</p>
              <p className="text-sm text-gray-500 mt-1">
                Create a subscription to start making recurring payments
              </p>
            </CardContent>
          </Card>
        )}
      </div>

      {/* Incoming Subscriptions */}
      <div>
        <h2 className="text-xl font-semibold mb-4">Incoming Subscriptions</h2>
        {loadingIncoming ? (
          <Card>
            <CardContent className="p-8 text-center">
              <Clock className="h-8 w-8 animate-spin text-gray-400 mx-auto" />
            </CardContent>
          </Card>
        ) : incomingSubscriptions && incomingSubscriptions.length > 0 ? (
          <div className="grid gap-4 md:grid-cols-2">
            {incomingSubscriptions.map((id) => (
              <SubscriptionCard
                key={id}
                subscriptionId={id}
                isRecipientView
                onUpdate={() => refetchIncoming()}
              />
            ))}
          </div>
        ) : (
          <Card>
            <CardContent className="p-8 text-center">
              <Users className="h-12 w-12 text-gray-600 mx-auto mb-4" />
              <p className="text-gray-400">No subscribers yet</p>
              <p className="text-sm text-gray-500 mt-1">
                Share your address to receive subscription payments
              </p>
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  )
}
