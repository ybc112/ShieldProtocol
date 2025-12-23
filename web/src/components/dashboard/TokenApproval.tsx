'use client'

import { useEffect } from 'react'
import { Check, Loader2, AlertCircle } from 'lucide-react'
import { Button, Card, CardContent } from '@/components/ui'
import { useTokenBalance, useTokenAllowance, useApproveToken } from '@/hooks'
import { CONTRACT_ADDRESSES } from '@/lib/contracts'
import { formatUnits } from 'viem'
import type { TokenInfo } from '@/types'

interface TokenApprovalProps {
  token: TokenInfo
  requiredAmount: bigint
  spender?: `0x${string}`
  onApprovalComplete?: () => void
}

export function TokenApproval({
  token,
  requiredAmount,
  spender = CONTRACT_ADDRESSES.dcaExecutor,
  onApprovalComplete,
}: TokenApprovalProps) {
  const { balance, isLoading: isLoadingBalance } = useTokenBalance(token.address as `0x${string}`)
  const { allowance, isLoading: isLoadingAllowance, refetch: refetchAllowance } = useTokenAllowance(
    token.address as `0x${string}`,
    spender
  )
  const { approve, isPending, isConfirming, isSuccess, error, reset } = useApproveToken()

  const hasEnoughBalance = balance !== undefined && balance >= requiredAmount
  const hasEnoughAllowance = allowance !== undefined && allowance >= requiredAmount
  const isApproved = hasEnoughAllowance

  useEffect(() => {
    if (isSuccess) {
      refetchAllowance()
      onApprovalComplete?.()
    }
  }, [isSuccess, refetchAllowance, onApprovalComplete])

  const handleApprove = async () => {
    reset()
    await approve(token.address as `0x${string}`, spender)
  }

  const formatAmount = (amount: bigint) => {
    return parseFloat(formatUnits(amount, token.decimals)).toLocaleString(undefined, {
      minimumFractionDigits: 2,
      maximumFractionDigits: 6,
    })
  }

  if (isLoadingBalance || isLoadingAllowance) {
    return (
      <Card>
        <CardContent className="p-4">
          <div className="flex items-center space-x-3">
            <Loader2 className="h-5 w-5 animate-spin text-gray-400" />
            <span className="text-sm text-gray-400">Checking {token.symbol} allowance...</span>
          </div>
        </CardContent>
      </Card>
    )
  }

  if (!hasEnoughBalance) {
    return (
      <Card className="border-red-600/30">
        <CardContent className="p-4">
          <div className="flex items-start space-x-3">
            <AlertCircle className="h-5 w-5 text-red-400 mt-0.5" />
            <div>
              <p className="text-sm font-medium text-red-400">Insufficient {token.symbol} Balance</p>
              <p className="text-xs text-gray-500 mt-1">
                You have {balance ? formatAmount(balance) : '0'} {token.symbol}, but need {formatAmount(requiredAmount)} {token.symbol}
              </p>
            </div>
          </div>
        </CardContent>
      </Card>
    )
  }

  if (isApproved) {
    return (
      <Card className="border-green-600/30">
        <CardContent className="p-4">
          <div className="flex items-center space-x-3">
            <div className="p-1.5 rounded-full bg-green-600/20">
              <Check className="h-4 w-4 text-green-400" />
            </div>
            <div>
              <p className="text-sm font-medium text-green-400">{token.symbol} Approved</p>
              <p className="text-xs text-gray-500">
                Allowance: {formatAmount(allowance!)} {token.symbol}
              </p>
            </div>
          </div>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card className="border-yellow-600/30">
      <CardContent className="p-4">
        <div className="flex items-start justify-between">
          <div className="flex items-start space-x-3">
            <AlertCircle className="h-5 w-5 text-yellow-400 mt-0.5" />
            <div>
              <p className="text-sm font-medium text-yellow-400">Approve {token.symbol}</p>
              <p className="text-xs text-gray-500 mt-1">
                Allow DCA Executor to spend your {token.symbol} for automated swaps
              </p>
              {error && (
                <p className="text-xs text-red-400 mt-2">
                  {error.message}
                </p>
              )}
            </div>
          </div>
          <Button
            size="sm"
            onClick={handleApprove}
            loading={isPending || isConfirming}
            disabled={isPending || isConfirming}
          >
            {isPending ? 'Confirming...' : isConfirming ? 'Approving...' : 'Approve'}
          </Button>
        </div>
      </CardContent>
    </Card>
  )
}
