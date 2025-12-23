import { config, validateConfig } from './config/index.js'
import { Scheduler } from './jobs/scheduler.js'
import { formatUnits } from 'viem'

async function main() {
  console.log('\n')
  console.log('╔═══════════════════════════════════════════════════════════╗')
  console.log('║                                                           ║')
  console.log('║         🛡️  Shield Protocol Execution Service            ║')
  console.log('║                                                           ║')
  console.log('╚═══════════════════════════════════════════════════════════╝')
  console.log('\n')

  // Validate configuration
  try {
    validateConfig()
  } catch (error: any) {
    console.error('❌ Configuration error:', error.message)
    console.error('\nPlease check your .env file and ensure all required variables are set.')
    console.error('See .env.example for reference.')
    process.exit(1)
  }

  // Create scheduler
  const scheduler = new Scheduler()

  // Get and display initial status
  const status = await scheduler.getStatus()
  console.log('\n📊 Executor Status:')
  console.log(`   Balance: ${status.dcaExecutorBalance}`)
  console.log(`   Execution enabled: ${config.enableExecution}`)

  // Warn if balance is low
  const balanceInEth = parseFloat(status.dcaExecutorBalance)
  if (balanceInEth < 0.01) {
    console.warn('\n⚠️  Warning: Executor balance is low!')
    console.warn('   Please fund the executor wallet with ETH for gas.')
  }

  // Handle command line arguments
  const args = process.argv.slice(2)

  if (args.includes('--run-once')) {
    // Run once and exit (useful for testing)
    console.log('\n🔄 Running immediate execution (--run-once mode)...')
    await scheduler.runNow()
    console.log('\n✅ Execution complete. Exiting.')
    process.exit(0)
  }

  // Start the scheduler
  scheduler.start()

  // Handle graceful shutdown
  process.on('SIGINT', () => {
    console.log('\n\n🛑 Received SIGINT. Shutting down...')
    scheduler.stop()
    process.exit(0)
  })

  process.on('SIGTERM', () => {
    console.log('\n\n🛑 Received SIGTERM. Shutting down...')
    scheduler.stop()
    process.exit(0)
  })

  // Keep the process running
  console.log('Press Ctrl+C to stop the service.\n')
}

// Run main
main().catch((error) => {
  console.error('Fatal error:', error)
  process.exit(1)
})
