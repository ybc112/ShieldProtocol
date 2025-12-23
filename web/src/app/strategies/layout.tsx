import { Sidebar } from '@/components/layout'

export default function StrategiesLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="flex-1 lg:pl-64">
        <div className="container mx-auto px-6 py-8">
          {children}
        </div>
      </main>
    </div>
  )
}
