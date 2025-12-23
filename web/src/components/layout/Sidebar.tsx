'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useAccount, useDisconnect } from 'wagmi'
import {
  LayoutDashboard,
  TrendingUp,
  Shield,
  PlusCircle,
  History,
  BarChart3,
  LogOut,
  Wallet,
  CreditCard,
  RefreshCw,
  ShieldAlert
} from 'lucide-react'
import { cn } from '@/lib/utils'

const mainNavigation = [
  { name: 'Dashboard', href: '/dashboard', icon: LayoutDashboard },
  { name: 'My Strategies', href: '/strategies', icon: TrendingUp },
  { name: 'Subscriptions', href: '/subscribe', icon: CreditCard },
]

const strategyNavigation = [
  { name: 'DCA Strategy', href: '/strategies/new', icon: PlusCircle },
  { name: 'Rebalance', href: '/strategies/rebalance', icon: RefreshCw },
  { name: 'Stop-Loss', href: '/strategies/stop-loss', icon: ShieldAlert },
]

const settingsNavigation = [
  { name: 'Shield Settings', href: '/shield', icon: Shield },
  { name: 'Activity Log', href: '/activity', icon: History },
  { name: 'Analytics', href: '/analytics', icon: BarChart3 },
]

export function Sidebar() {
  const pathname = usePathname()
  const { address, isConnected } = useAccount()
  const { disconnect } = useDisconnect()

  const formatAddress = (addr: string) => {
    return `${addr.slice(0, 6)}...${addr.slice(-4)}`
  }

  return (
    <aside className="hidden lg:flex lg:flex-col lg:w-64 lg:fixed lg:inset-y-0 border-r border-gray-800 bg-gray-900/50">
      <div className="flex flex-col flex-1 overflow-y-auto">
        {/* Logo */}
        <div className="px-4 py-5 border-b border-gray-800">
          <Link href="/dashboard" className="flex items-center space-x-2">
            <Shield className="h-8 w-8 text-primary-400" />
            <span className="text-xl font-bold text-white">Shield Protocol</span>
          </Link>
        </div>

        <div className="flex flex-col flex-1 px-4 py-6">
          {/* Main Navigation */}
          <nav className="space-y-1">
            <p className="px-3 text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">
              Main
            </p>
            {mainNavigation.map((item) => {
              const Icon = item.icon
              const isActive = pathname === item.href
              return (
                <Link
                  key={item.name}
                  href={item.href}
                  className={cn(
                    'flex items-center space-x-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors',
                    isActive
                      ? 'bg-primary-600/20 text-primary-400 border border-primary-600/30'
                      : 'text-gray-400 hover:text-gray-100 hover:bg-gray-800'
                  )}
                >
                  <Icon className="h-5 w-5" />
                  <span>{item.name}</span>
                </Link>
              )
            })}
          </nav>

          {/* Strategy Navigation */}
          <nav className="mt-6 space-y-1">
            <p className="px-3 text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">
              Create Strategy
            </p>
            {strategyNavigation.map((item) => {
              const Icon = item.icon
              const isActive = pathname === item.href
              return (
                <Link
                  key={item.name}
                  href={item.href}
                  className={cn(
                    'flex items-center space-x-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors',
                    isActive
                      ? 'bg-primary-600/20 text-primary-400 border border-primary-600/30'
                      : 'text-gray-400 hover:text-gray-100 hover:bg-gray-800'
                  )}
                >
                  <Icon className="h-5 w-5" />
                  <span>{item.name}</span>
                </Link>
              )
            })}
          </nav>

          {/* Settings Navigation */}
          <nav className="mt-8 space-y-1">
            <p className="px-3 text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2">
              Settings
            </p>
            {settingsNavigation.map((item) => {
              const Icon = item.icon
              const isActive = pathname === item.href
              return (
                <Link
                  key={item.name}
                  href={item.href}
                  className={cn(
                    'flex items-center space-x-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors',
                    isActive
                      ? 'bg-primary-600/20 text-primary-400 border border-primary-600/30'
                      : 'text-gray-400 hover:text-gray-100 hover:bg-gray-800'
                  )}
                >
                  <Icon className="h-5 w-5" />
                  <span>{item.name}</span>
                </Link>
              )
            })}
          </nav>

          {/* Bottom Section */}
          <div className="mt-auto pt-6 space-y-3">
            {/* Wallet Connection */}
            {isConnected && address ? (
              <div className="px-3 py-3 rounded-lg bg-gray-800/50 border border-gray-700">
                <div className="flex items-center space-x-2 mb-2">
                  <Wallet className="h-4 w-4 text-primary-400" />
                  <span className="text-sm font-medium text-gray-200">
                    {formatAddress(address)}
                  </span>
                </div>
                <button
                  onClick={() => disconnect()}
                  className="flex items-center space-x-2 w-full px-2 py-1.5 rounded text-xs text-gray-400 hover:text-red-400 hover:bg-gray-700 transition-colors"
                >
                  <LogOut className="h-3.5 w-3.5" />
                  <span>Disconnect</span>
                </button>
              </div>
            ) : (
              <div className="px-3 py-3 rounded-lg bg-gray-800/50 border border-gray-700">
                <p className="text-xs text-gray-500 mb-2">Not connected</p>
              </div>
            )}

            {/* Network Status */}
            <div className="px-3 py-2 rounded-lg bg-gray-800/50">
              <div className="flex items-center space-x-2">
                <div className="w-2 h-2 rounded-full bg-green-500" />
                <span className="text-xs text-gray-400">Sepolia Testnet</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </aside>
  )
}
