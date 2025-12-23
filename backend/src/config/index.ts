import 'dotenv/config'

export const config = {
  // RPC
  rpcUrl: process.env.SEPOLIA_RPC_URL || 'https://rpc.sepolia.org',

  // Executor wallet
  executorPrivateKey: process.env.EXECUTOR_PRIVATE_KEY || '',

  // Cron schedule
  cronSchedule: process.env.CRON_SCHEDULE || '*/5 * * * *',

  // Execution control
  enableExecution: process.env.ENABLE_EXECUTION !== 'false',

  // Log level
  logLevel: process.env.LOG_LEVEL || 'info',

  // Chain
  chainId: 11155111, // Sepolia

  // Ponder Indexer
  indexerUrl: process.env.INDEXER_URL || 'http://localhost:42069',
  indexerGraphqlUrl: process.env.INDEXER_GRAPHQL_URL || 'http://localhost:42069/graphql',
}

export function validateConfig() {
  if (!config.executorPrivateKey) {
    throw new Error('EXECUTOR_PRIVATE_KEY is required')
  }

  if (!config.rpcUrl) {
    throw new Error('SEPOLIA_RPC_URL is required')
  }

  console.log('Configuration validated successfully')
  console.log(`  RPC URL: ${config.rpcUrl.slice(0, 30)}...`)
  console.log(`  Execution enabled: ${config.enableExecution}`)
  console.log(`  Cron schedule: ${config.cronSchedule}`)
}
