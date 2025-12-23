'use client'

import Link from 'next/link'
import { useAccount } from 'wagmi'
import { Shield, ArrowRight, Zap, Lock, TrendingUp, Bell } from 'lucide-react'
import { Button } from '@/components/ui'

const features = [
  {
    icon: Lock,
    title: 'Smart Shield Protection',
    description: 'Set daily and single transaction limits to protect your assets from unauthorized spending.',
  },
  {
    icon: TrendingUp,
    title: 'Automated DCA Strategies',
    description: 'Create dollar-cost averaging strategies that execute automatically without daily intervention.',
  },
  {
    icon: Zap,
    title: 'One-time Authorization',
    description: 'Grant precise permissions once and let your strategies run automatically.',
  },
  {
    icon: Bell,
    title: 'Emergency Controls',
    description: 'Instantly freeze all operations with emergency mode when you detect suspicious activity.',
  },
]

export default function HomePage() {
  const { isConnected } = useAccount()

  return (
    <main className="min-h-screen">
      {/* Hero Section */}
      <section className="relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-primary-900/20 via-gray-950 to-gray-950" />
        <div className="absolute inset-0 bg-[url('/grid.svg')] bg-center [mask-image:linear-gradient(180deg,white,rgba(255,255,255,0))]" />

        <div className="relative container mx-auto px-4 py-24 sm:py-32">
          <div className="text-center max-w-4xl mx-auto">
            <div className="flex justify-center mb-6">
              <div className="p-4 rounded-2xl bg-primary-600/20 border border-primary-600/30">
                <Shield className="h-16 w-16 text-primary-400" />
              </div>
            </div>

            <h1 className="text-4xl sm:text-6xl font-bold mb-6">
              <span className="bg-gradient-to-r from-primary-400 via-blue-400 to-green-400 bg-clip-text text-transparent">
                Shield Protocol
              </span>
            </h1>

            <p className="text-xl sm:text-2xl text-gray-400 mb-8 max-w-2xl mx-auto">
              Intent-driven asset protection and automation platform.
              Set limits, automate strategies, and stay in control.
            </p>

            <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
              {isConnected ? (
                <Link href="/dashboard">
                  <Button size="lg" className="group">
                    Go to Dashboard
                    <ArrowRight className="ml-2 h-5 w-5 group-hover:translate-x-1 transition-transform" />
                  </Button>
                </Link>
              ) : (
                <Button size="lg" className="group" disabled>
                  Connect Wallet to Start
                  <ArrowRight className="ml-2 h-5 w-5" />
                </Button>
              )}
              <Link href="/strategies/new">
                <Button variant="outline" size="lg">
                  Create Strategy
                </Button>
              </Link>
            </div>

            {/* Stats */}
            <div className="grid grid-cols-3 gap-8 mt-16 max-w-2xl mx-auto">
              <div className="text-center">
                <p className="text-3xl font-bold text-primary-400">$0</p>
                <p className="text-sm text-gray-500">Total Protected</p>
              </div>
              <div className="text-center">
                <p className="text-3xl font-bold text-green-400">0</p>
                <p className="text-sm text-gray-500">Active Strategies</p>
              </div>
              <div className="text-center">
                <p className="text-3xl font-bold text-blue-400">Sepolia</p>
                <p className="text-sm text-gray-500">Network</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section className="py-24 border-t border-gray-800">
        <div className="container mx-auto px-4">
          <div className="text-center mb-16">
            <h2 className="text-3xl font-bold mb-4">Powerful Features</h2>
            <p className="text-gray-400 max-w-2xl mx-auto">
              Shield Protocol combines advanced permission controls with automated execution
              to give you complete control over your DeFi activities.
            </p>
          </div>

          <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-6">
            {features.map((feature) => {
              const Icon = feature.icon
              return (
                <div
                  key={feature.title}
                  className="p-6 rounded-xl bg-gray-900/50 border border-gray-800 hover:border-gray-700 transition-colors"
                >
                  <div className="p-3 rounded-lg bg-primary-600/20 w-fit mb-4">
                    <Icon className="h-6 w-6 text-primary-400" />
                  </div>
                  <h3 className="text-lg font-semibold mb-2">{feature.title}</h3>
                  <p className="text-sm text-gray-400">{feature.description}</p>
                </div>
              )
            })}
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="py-24 border-t border-gray-800">
        <div className="container mx-auto px-4">
          <div className="max-w-3xl mx-auto text-center">
            <h2 className="text-3xl font-bold mb-4">Ready to Protect Your Assets?</h2>
            <p className="text-gray-400 mb-8">
              Connect your wallet and start using Shield Protocol today.
              Deploy on Sepolia testnet to explore all features risk-free.
            </p>
            <Link href="/dashboard">
              <Button size="lg">
                Get Started
                <ArrowRight className="ml-2 h-5 w-5" />
              </Button>
            </Link>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-8 border-t border-gray-800">
        <div className="container mx-auto px-4">
          <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
            <div className="flex items-center space-x-2">
              <Shield className="h-5 w-5 text-primary-500" />
              <span className="text-sm text-gray-400">Shield Protocol</span>
            </div>
            <p className="text-sm text-gray-500">
              Built for MetaMask ERC-7715 Advanced Permissions
            </p>
          </div>
        </div>
      </footer>
    </main>
  )
}
