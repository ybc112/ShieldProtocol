import type { Metadata } from 'next'
import './globals.css'
import { Providers } from '@/components/Providers'

export const metadata: Metadata = {
  title: 'Shield Protocol - Smart Asset Protection',
  description: 'Intent-driven asset protection and automation platform powered by ERC-7715',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en" className="dark">
      <body className="font-sans antialiased">
        <Providers>
          <div className="min-h-screen bg-gray-950">
            {children}
          </div>
        </Providers>
      </body>
    </html>
  )
}
