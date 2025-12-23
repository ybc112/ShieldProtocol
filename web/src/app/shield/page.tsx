'use client'

import { useState, useEffect } from 'react'
import { useAccount } from 'wagmi'
import { Shield, AlertTriangle, Settings, Plus, Trash2, CheckCircle } from 'lucide-react'
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
import {
  useShieldConfig,
  useActivateShield,
  useDeactivateShield,
  useEmergencyMode,
  useWhitelist,
  useRemainingAllowance,
} from '@/hooks'
import { ConnectPrompt } from '@/components/dashboard/ConnectPrompt'
import { formatTokenAmount, shortenAddress } from '@/lib/utils'
import { parseUnits } from 'viem'

export default function ShieldSettingsPage() {
  const { address, isConnected } = useAccount()
  const { config, isLoading: isLoadingConfig, refetch } = useShieldConfig()
  const { remainingAllowance } = useRemainingAllowance()
  const { activate, isPending: isActivating, isSuccess: activateSuccess } = useActivateShield()
  const { deactivate, isPending: isDeactivating } = useDeactivateShield()
  const { enableEmergency, disableEmergency, isPending: isEmergencyPending } = useEmergencyMode()
  const {
    whitelistedContracts,
    addToWhitelist,
    removeFromWhitelist,
    isPending: isWhitelistPending,
    refetch: refetchWhitelist,
  } = useWhitelist()

  // Form state
  const [dailyLimit, setDailyLimit] = useState('1000')
  const [singleTxLimit, setSingleTxLimit] = useState('100')
  const [newWhitelistAddress, setNewWhitelistAddress] = useState('')

  // Refetch on success
  useEffect(() => {
    if (activateSuccess) {
      refetch()
    }
  }, [activateSuccess, refetch])

  if (!isConnected) {
    return <ConnectPrompt />
  }

  const handleActivate = async () => {
    try {
      const dailyLimitBigInt = parseUnits(dailyLimit, 6)
      const singleTxLimitBigInt = parseUnits(singleTxLimit, 6)
      await activate(dailyLimitBigInt, singleTxLimitBigInt)
    } catch (error) {
      console.error('Failed to activate shield:', error)
    }
  }

  const handleAddWhitelist = async () => {
    if (!newWhitelistAddress || !newWhitelistAddress.startsWith('0x')) return
    try {
      await addToWhitelist(newWhitelistAddress as `0x${string}`)
      setNewWhitelistAddress('')
      refetchWhitelist()
    } catch (error) {
      console.error('Failed to add to whitelist:', error)
    }
  }

  return (
    <div className="space-y-8">
      {/* Page Header */}
      <div>
        <h1 className="text-3xl font-bold">Shield Settings</h1>
        <p className="text-gray-400 mt-1">
          Configure your asset protection settings
        </p>
      </div>

      {/* Shield Status Card */}
      <Card className={config?.isActive ? 'border-green-500/30' : 'border-yellow-500/30'}>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-3">
              <div className={`p-3 rounded-lg ${config?.isActive ? 'bg-green-600/20' : 'bg-yellow-600/20'}`}>
                <Shield className={`h-6 w-6 ${config?.isActive ? 'text-green-500' : 'text-yellow-500'}`} />
              </div>
              <div>
                <CardTitle>Shield Protection</CardTitle>
                <CardDescription>
                  {config?.isActive ? 'Your assets are protected' : 'Shield is not active'}
                </CardDescription>
              </div>
            </div>
            <Badge variant={config?.isActive ? 'success' : 'warning'}>
              {config?.isActive ? 'Active' : 'Inactive'}
            </Badge>
          </div>
        </CardHeader>
        <CardContent>
          {config?.isActive ? (
            <div className="space-y-4">
              <div className="grid gap-4 md:grid-cols-2">
                <div className="p-4 rounded-lg bg-gray-800/50">
                  <p className="text-sm text-gray-400 mb-1">Daily Spend Limit</p>
                  <p className="text-xl font-semibold">
                    {formatTokenAmount(config.dailySpendLimit, 6)} USDC
                  </p>
                </div>
                <div className="p-4 rounded-lg bg-gray-800/50">
                  <p className="text-sm text-gray-400 mb-1">Single Transaction Limit</p>
                  <p className="text-xl font-semibold">
                    {formatTokenAmount(config.singleTxLimit, 6)} USDC
                  </p>
                </div>
              </div>

              {/* Spending Progress Bar */}
              <div className="p-4 rounded-lg bg-gray-800/50">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-sm font-medium text-gray-300">Today&apos;s Usage</span>
                  <span className={`text-sm font-semibold ${
                    Number(config.spentToday) / Number(config.dailySpendLimit) > 0.8
                      ? 'text-red-400'
                      : Number(config.spentToday) / Number(config.dailySpendLimit) > 0.5
                      ? 'text-yellow-400'
                      : 'text-green-400'
                  }`}>
                    {((Number(config.spentToday) / Number(config.dailySpendLimit)) * 100).toFixed(1)}%
                  </span>
                </div>
                <div className="relative h-4 w-full overflow-hidden rounded-full bg-gray-700 mb-2">
                  <div
                    className={`h-full transition-all duration-300 ${
                      Number(config.spentToday) / Number(config.dailySpendLimit) > 0.8
                        ? 'bg-gradient-to-r from-red-600 to-red-400'
                        : Number(config.spentToday) / Number(config.dailySpendLimit) > 0.5
                        ? 'bg-gradient-to-r from-yellow-600 to-yellow-400'
                        : 'bg-gradient-to-r from-green-600 to-green-400'
                    }`}
                    style={{ width: `${Math.min((Number(config.spentToday) / Number(config.dailySpendLimit)) * 100, 100)}%` }}
                  />
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-gray-400">
                    Spent: <span className="text-gray-200">{formatTokenAmount(config.spentToday, 6)} USDC</span>
                  </span>
                  <span className="text-gray-400">
                    Remaining: <span className="text-green-400">{formatTokenAmount(config.dailySpendLimit - config.spentToday, 6)} USDC</span>
                  </span>
                </div>
              </div>

              <Button
                variant="outline"
                onClick={() => deactivate()}
                loading={isDeactivating}
                className="w-full"
              >
                Deactivate Shield
              </Button>
            </div>
          ) : (
            <div className="space-y-4">
              <p className="text-sm text-gray-400">
                Activate Shield to set spending limits and protect your assets from unauthorized transactions.
              </p>
              <div className="grid gap-4 md:grid-cols-2">
                <Input
                  label="Daily Spend Limit (USDC)"
                  type="number"
                  value={dailyLimit}
                  onChange={(e) => setDailyLimit(e.target.value)}
                  placeholder="1000"
                />
                <Input
                  label="Single Transaction Limit (USDC)"
                  type="number"
                  value={singleTxLimit}
                  onChange={(e) => setSingleTxLimit(e.target.value)}
                  placeholder="100"
                />
              </div>
              <Button
                onClick={handleActivate}
                loading={isActivating}
                className="w-full"
              >
                <Shield className="mr-2 h-4 w-4" />
                Activate Shield
              </Button>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Emergency Mode */}
      <Card className={config?.emergencyMode ? 'border-red-500' : ''}>
        <CardHeader>
          <div className="flex items-center space-x-3">
            <div className={`p-3 rounded-lg ${config?.emergencyMode ? 'bg-red-600/20' : 'bg-gray-800'}`}>
              <AlertTriangle className={`h-6 w-6 ${config?.emergencyMode ? 'text-red-500' : 'text-gray-400'}`} />
            </div>
            <div>
              <CardTitle>Emergency Mode</CardTitle>
              <CardDescription>
                Instantly freeze all automated operations
              </CardDescription>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          {config?.emergencyMode ? (
            <div className="space-y-4">
              <div className="p-4 rounded-lg bg-red-600/10 border border-red-600/30">
                <div className="flex items-center space-x-2 text-red-400 mb-2">
                  <AlertTriangle className="h-5 w-5" />
                  <span className="font-semibold">Emergency Mode Active</span>
                </div>
                <p className="text-sm text-gray-400">
                  All automated operations are currently frozen. No strategies will execute until you disable emergency mode.
                </p>
              </div>
              <Button
                variant="outline"
                onClick={() => disableEmergency()}
                loading={isEmergencyPending}
                className="w-full"
              >
                <CheckCircle className="mr-2 h-4 w-4" />
                Disable Emergency Mode
              </Button>
            </div>
          ) : (
            <div className="space-y-4">
              <p className="text-sm text-gray-400">
                If you suspect unauthorized activity, enable emergency mode to immediately stop all automated transactions.
              </p>
              <Button
                variant="destructive"
                onClick={() => enableEmergency()}
                loading={isEmergencyPending}
                disabled={!config?.isActive}
                className="w-full"
              >
                <AlertTriangle className="mr-2 h-4 w-4" />
                Enable Emergency Mode
              </Button>
              {!config?.isActive && (
                <p className="text-xs text-gray-500 text-center">
                  Activate Shield first to use emergency mode
                </p>
              )}
            </div>
          )}
        </CardContent>
      </Card>

      {/* Whitelist Management */}
      <Card>
        <CardHeader>
          <div className="flex items-center space-x-3">
            <div className="p-3 rounded-lg bg-gray-800">
              <Settings className="h-6 w-6 text-gray-400" />
            </div>
            <div>
              <CardTitle>Contract Whitelist</CardTitle>
              <CardDescription>
                Only allow interactions with trusted contracts
              </CardDescription>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {/* Add new address */}
            <div className="flex space-x-2">
              <Input
                placeholder="0x..."
                value={newWhitelistAddress}
                onChange={(e) => setNewWhitelistAddress(e.target.value)}
                disabled={!config?.isActive}
              />
              <Button
                onClick={handleAddWhitelist}
                loading={isWhitelistPending}
                disabled={!config?.isActive || !newWhitelistAddress}
              >
                <Plus className="h-4 w-4" />
              </Button>
            </div>

            {/* Whitelisted contracts */}
            {whitelistedContracts && whitelistedContracts.length > 0 ? (
              <div className="space-y-2">
                {whitelistedContracts.map((contract) => (
                  <div
                    key={contract}
                    className="flex items-center justify-between p-3 rounded-lg bg-gray-800/50"
                  >
                    <div className="flex items-center space-x-2">
                      <CheckCircle className="h-4 w-4 text-green-500" />
                      <span className="text-sm font-mono">{shortenAddress(contract, 8)}</span>
                    </div>
                    <button
                      onClick={() => removeFromWhitelist(contract)}
                      className="p-1.5 rounded hover:bg-gray-700 text-gray-400 hover:text-red-500"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </div>
                ))}
              </div>
            ) : (
              <p className="text-sm text-gray-500 text-center py-4">
                No contracts whitelisted yet. All contracts are currently allowed.
              </p>
            )}

            {!config?.isActive && (
              <p className="text-xs text-gray-500 text-center">
                Activate Shield to manage whitelist
              </p>
            )}
          </div>
        </CardContent>
      </Card>

      {/* Account Info */}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Account Information</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid gap-4 md:grid-cols-2">
            <div className="p-4 rounded-lg bg-gray-800/50">
              <p className="text-xs text-gray-500 mb-1">Connected Address</p>
              <p className="text-sm font-mono">{address}</p>
            </div>
            <div className="p-4 rounded-lg bg-gray-800/50">
              <p className="text-xs text-gray-500 mb-1">Network</p>
              <p className="text-sm">Sepolia Testnet</p>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
