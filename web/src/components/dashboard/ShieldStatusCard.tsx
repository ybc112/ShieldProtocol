'use client'

import { Shield, CheckCircle2, XCircle } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle, Badge } from '@/components/ui'
import type { ShieldConfig } from '@/types'

interface ShieldStatusCardProps {
  config: ShieldConfig | null
  isLoading: boolean
}

export function ShieldStatusCard({ config, isLoading }: ShieldStatusCardProps) {
  if (isLoading) {
    return (
      <Card>
        <CardHeader className="flex flex-row items-center justify-between pb-2">
          <CardTitle className="text-sm font-medium text-gray-400">
            Shield Status
          </CardTitle>
          <Shield className="h-4 w-4 text-gray-500" />
        </CardHeader>
        <CardContent>
          <div className="animate-pulse">
            <div className="h-6 w-24 bg-gray-700 rounded" />
            <div className="h-4 w-32 bg-gray-800 rounded mt-2" />
          </div>
        </CardContent>
      </Card>
    )
  }

  const isActive = config?.isActive ?? false

  return (
    <Card className={isActive ? 'border-green-500/30' : 'border-yellow-500/30'}>
      <CardHeader className="flex flex-row items-center justify-between pb-2">
        <CardTitle className="text-sm font-medium text-gray-400">
          Shield Status
        </CardTitle>
        <Shield
          className={`h-4 w-4 ${isActive ? 'text-green-500' : 'text-yellow-500'}`}
        />
      </CardHeader>
      <CardContent>
        <div className="flex items-center space-x-2">
          {isActive ? (
            <>
              <CheckCircle2 className="h-5 w-5 text-green-500" />
              <span className="text-xl font-bold text-green-500">Active</span>
            </>
          ) : (
            <>
              <XCircle className="h-5 w-5 text-yellow-500" />
              <span className="text-xl font-bold text-yellow-500">Inactive</span>
            </>
          )}
        </div>
        <p className="text-xs text-gray-500 mt-2">
          {isActive
            ? 'Your assets are protected'
            : 'Activate Shield to protect your assets'}
        </p>
        {!isActive && (
          <a
            href="/shield"
            className="text-xs text-primary-400 hover:text-primary-300 mt-2 inline-block"
          >
            Activate Now →
          </a>
        )}
      </CardContent>
    </Card>
  )
}
