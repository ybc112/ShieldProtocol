'use client'

import * as React from 'react'
import { cn } from '@/lib/utils'

interface ProgressProps extends React.HTMLAttributes<HTMLDivElement> {
  value?: number
  max?: number
  showLabel?: boolean
}

const Progress = React.forwardRef<HTMLDivElement, ProgressProps>(
  ({ className, value = 0, max = 100, showLabel = false, ...props }, ref) => {
    const percentage = Math.min(Math.max((value / max) * 100, 0), 100)

    return (
      <div className="w-full">
        <div
          ref={ref}
          className={cn(
            'relative h-2 w-full overflow-hidden rounded-full bg-gray-800',
            className
          )}
          {...props}
        >
          <div
            className="h-full bg-gradient-to-r from-primary-500 to-primary-400 transition-all duration-300"
            style={{ width: `${percentage}%` }}
          />
        </div>
        {showLabel && (
          <div className="flex justify-between text-xs text-gray-400 mt-1">
            <span>{value.toLocaleString()}</span>
            <span>{max.toLocaleString()}</span>
          </div>
        )}
      </div>
    )
  }
)
Progress.displayName = 'Progress'

export { Progress }
