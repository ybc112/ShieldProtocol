'use client'

import * as React from 'react'
import { cn } from '@/lib/utils'

export interface BadgeProps extends React.HTMLAttributes<HTMLDivElement> {
  variant?: 'default' | 'secondary' | 'destructive' | 'success' | 'warning' | 'outline'
}

function Badge({ className, variant = 'default', ...props }: BadgeProps) {
  const variants = {
    default: 'bg-primary-600 text-white',
    secondary: 'bg-gray-700 text-gray-100',
    destructive: 'bg-red-600 text-white',
    success: 'bg-green-600 text-white',
    warning: 'bg-yellow-600 text-white',
    outline: 'border border-gray-600 text-gray-100',
  }

  return (
    <div
      className={cn(
        'inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold transition-colors',
        variants[variant],
        className
      )}
      {...props}
    />
  )
}

export { Badge }
