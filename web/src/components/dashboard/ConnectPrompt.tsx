'use client'

import { Wallet } from 'lucide-react'
import { useConnect } from 'wagmi'
import { Button, Card, CardContent } from '@/components/ui'

export function ConnectPrompt() {
  const { connect, connectors, isPending } = useConnect()

  const handleConnect = () => {
    const injectedConnector = connectors.find((c) => c.id === 'injected')
    if (injectedConnector) {
      connect({ connector: injectedConnector })
    }
  }

  return (
    <div className="flex items-center justify-center min-h-[60vh]">
      <Card className="max-w-md w-full">
        <CardContent className="p-8 text-center">
          <div className="p-4 rounded-full bg-primary-600/20 w-fit mx-auto mb-6">
            <Wallet className="h-8 w-8 text-primary-400" />
          </div>
          <h2 className="text-2xl font-bold mb-2">Connect Your Wallet</h2>
          <p className="text-gray-400 mb-6">
            Connect your wallet to view your dashboard and manage your Shield
            Protocol settings.
          </p>
          <Button onClick={handleConnect} loading={isPending} className="w-full">
            Connect Wallet
          </Button>
          <p className="text-xs text-gray-500 mt-4">
            Make sure you&apos;re connected to Sepolia testnet
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
