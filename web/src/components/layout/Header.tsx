'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useAccount, useConnect, useDisconnect } from 'wagmi'
import { Shield, LayoutDashboard, Settings, TrendingUp, Menu, X } from 'lucide-react'
import { useState } from 'react'
import { Button } from '@/components/ui'
import { cn, shortenAddress } from '@/lib/utils'

const navigation = [
  { name: 'Dashboard', href: '/dashboard', icon: LayoutDashboard },
  { name: 'Strategies', href: '/strategies', icon: TrendingUp },
  { name: 'Shield Settings', href: '/shield', icon: Settings },
]

export function Header() {
  const pathname = usePathname()
  const { address, isConnected } = useAccount()
  const { connect, connectors, isPending } = useConnect()
  const { disconnect } = useDisconnect()
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)

  const handleConnect = () => {
    const injectedConnector = connectors.find((c) => c.id === 'injected')
    if (injectedConnector) {
      connect({ connector: injectedConnector })
    }
  }

  return (
    <header className="sticky top-0 z-50 w-full border-b border-gray-800 bg-gray-900/80 backdrop-blur-lg">
      <div className="container mx-auto flex h-16 items-center justify-between px-4">
        {/* Logo */}
        <Link href="/" className="flex items-center space-x-2">
          <Shield className="h-8 w-8 text-primary-500" />
          <span className="text-xl font-bold bg-gradient-to-r from-primary-400 to-green-400 bg-clip-text text-transparent">
            Shield Protocol
          </span>
        </Link>

        {/* Desktop Navigation */}
        <nav className="hidden md:flex items-center space-x-1">
          {navigation.map((item) => {
            const Icon = item.icon
            const isActive = pathname === item.href
            return (
              <Link
                key={item.name}
                href={item.href}
                className={cn(
                  'flex items-center space-x-2 px-4 py-2 rounded-lg text-sm font-medium transition-colors',
                  isActive
                    ? 'bg-primary-600/20 text-primary-400'
                    : 'text-gray-400 hover:text-gray-100 hover:bg-gray-800'
                )}
              >
                <Icon className="h-4 w-4" />
                <span>{item.name}</span>
              </Link>
            )
          })}
        </nav>

        {/* Wallet Connection */}
        <div className="flex items-center space-x-4">
          {isConnected ? (
            <div className="flex items-center space-x-3">
              <div className="hidden sm:flex items-center space-x-2 px-3 py-1.5 rounded-lg bg-gray-800 border border-gray-700">
                <div className="w-2 h-2 rounded-full bg-green-500" />
                <span className="text-sm text-gray-300">{shortenAddress(address!)}</span>
              </div>
              <Button variant="outline" size="sm" onClick={() => disconnect()}>
                Disconnect
              </Button>
            </div>
          ) : (
            <Button onClick={handleConnect} loading={isPending}>
              Connect Wallet
            </Button>
          )}

          {/* Mobile Menu Button */}
          <button
            className="md:hidden p-2 rounded-lg hover:bg-gray-800"
            onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
          >
            {mobileMenuOpen ? (
              <X className="h-6 w-6" />
            ) : (
              <Menu className="h-6 w-6" />
            )}
          </button>
        </div>
      </div>

      {/* Mobile Menu */}
      {mobileMenuOpen && (
        <div className="md:hidden border-t border-gray-800 bg-gray-900">
          <nav className="container mx-auto px-4 py-4 space-y-2">
            {navigation.map((item) => {
              const Icon = item.icon
              const isActive = pathname === item.href
              return (
                <Link
                  key={item.name}
                  href={item.href}
                  onClick={() => setMobileMenuOpen(false)}
                  className={cn(
                    'flex items-center space-x-3 px-4 py-3 rounded-lg text-sm font-medium transition-colors',
                    isActive
                      ? 'bg-primary-600/20 text-primary-400'
                      : 'text-gray-400 hover:text-gray-100 hover:bg-gray-800'
                  )}
                >
                  <Icon className="h-5 w-5" />
                  <span>{item.name}</span>
                </Link>
              )
            })}
          </nav>
        </div>
      )}
    </header>
  )
}
