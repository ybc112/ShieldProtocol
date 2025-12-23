import { onchainTable, relations } from "ponder";

// ==================== User & Shield Tables ====================

export const user = onchainTable("user", (t) => ({
  id: t.text().primaryKey(), // User address (lowercase)
  address: t.text().notNull(),
  totalInvested: t.bigint().notNull().default(0n),
  totalReceived: t.bigint().notNull().default(0n),
  totalDCAExecutions: t.integer().notNull().default(0),
  totalPaymentsMade: t.integer().notNull().default(0),
  totalPaymentsReceived: t.integer().notNull().default(0),
  createdAt: t.bigint().notNull(),
  updatedAt: t.bigint().notNull(),
}));

export const shield = onchainTable("shield", (t) => ({
  id: t.text().primaryKey(), // Same as user address
  userId: t.text().notNull(),
  dailySpendLimit: t.bigint().notNull(),
  singleTxLimit: t.bigint().notNull(),
  spentToday: t.bigint().notNull().default(0n),
  lastResetTimestamp: t.bigint().notNull(),
  isActive: t.boolean().notNull().default(true),
  emergencyMode: t.boolean().notNull().default(false),
  activatedAt: t.bigint().notNull(),
  updatedAt: t.bigint().notNull(),
}));

export const whitelistedContract = onchainTable("whitelisted_contract", (t) => ({
  id: t.text().primaryKey(), // shieldId-contractAddress
  shieldId: t.text().notNull(),
  contractAddress: t.text().notNull(),
  addedAt: t.bigint().notNull(),
  isActive: t.boolean().notNull().default(true),
}));

export const spendingRecord = onchainTable("spending_record", (t) => ({
  id: t.text().primaryKey(), // txHash-logIndex
  shieldId: t.text().notNull(),
  tokenId: t.text().notNull(),
  amount: t.bigint().notNull(),
  newDailyTotal: t.bigint().notNull(),
  txHash: t.text().notNull(),
  timestamp: t.bigint().notNull(),
}));

// ==================== DCA Strategy Tables ====================

export const dcaStrategy = onchainTable("dca_strategy", (t) => ({
  id: t.text().primaryKey(), // Strategy ID (bytes32)
  userId: t.text().notNull(),
  sourceTokenId: t.text().notNull(),
  targetTokenId: t.text().notNull(),
  amountPerExecution: t.bigint().notNull(),
  minAmountOut: t.bigint().notNull().default(0n),
  intervalSeconds: t.bigint().notNull(),
  totalExecutions: t.integer().notNull(),
  executionsCompleted: t.integer().notNull().default(0),
  status: t.text().notNull().default("Active"), // Active, Paused, Completed, Cancelled, AutoPaused
  totalAmountIn: t.bigint().notNull().default(0n),
  totalAmountOut: t.bigint().notNull().default(0n),
  averagePrice: t.bigint().notNull().default(0n),
  lastExecutionTime: t.bigint(),
  nextExecutionTime: t.bigint(),
  autoPausedReason: t.text(),
  createdAt: t.bigint().notNull(),
  updatedAt: t.bigint().notNull(),
}));

export const dcaExecution = onchainTable("dca_execution", (t) => ({
  id: t.text().primaryKey(), // txHash-logIndex
  strategyId: t.text().notNull(),
  amountIn: t.bigint().notNull(),
  amountOut: t.bigint().notNull(),
  price: t.bigint().notNull(),
  executionNumber: t.integer().notNull(),
  txHash: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  timestamp: t.bigint().notNull(),
}));

// ==================== Rebalance Strategy Tables ====================

export const rebalanceStrategy = onchainTable("rebalance_strategy", (t) => ({
  id: t.text().primaryKey(), // Strategy ID (bytes32)
  userId: t.text().notNull(),
  rebalanceThreshold: t.bigint().notNull(), // in basis points (e.g., 500 = 5%)
  minRebalanceInterval: t.bigint().notNull(),
  lastRebalanceTime: t.bigint(),
  totalRebalances: t.integer().notNull().default(0),
  totalValue: t.bigint().notNull().default(0n),
  poolFee: t.integer().notNull().default(3000),
  status: t.text().notNull().default("Active"), // Active, Paused, Cancelled
  createdAt: t.bigint().notNull(),
  updatedAt: t.bigint().notNull(),
}));

export const rebalanceAllocation = onchainTable("rebalance_allocation", (t) => ({
  id: t.text().primaryKey(), // strategyId-tokenAddress
  strategyId: t.text().notNull(),
  tokenId: t.text().notNull(),
  targetWeight: t.bigint().notNull(), // in basis points (e.g., 5000 = 50%)
  currentWeight: t.bigint().notNull().default(0n),
  createdAt: t.bigint().notNull(),
  updatedAt: t.bigint().notNull(),
}));

export const rebalanceExecution = onchainTable("rebalance_execution", (t) => ({
  id: t.text().primaryKey(), // txHash-logIndex
  strategyId: t.text().notNull(),
  totalValue: t.bigint().notNull(),
  rebalanceNumber: t.integer().notNull(),
  txHash: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  timestamp: t.bigint().notNull(),
}));

// ==================== Stop-Loss Strategy Tables ====================

export const stopLossStrategy = onchainTable("stop_loss_strategy", (t) => ({
  id: t.text().primaryKey(), // Strategy ID (bytes32)
  userId: t.text().notNull(),
  tokenToSellId: t.text().notNull(),
  tokenToReceiveId: t.text().notNull(),
  amount: t.bigint().notNull(),
  stopLossType: t.integer().notNull(), // 0: FixedPrice, 1: Percentage, 2: TrailingStop
  triggerPrice: t.bigint(), // for fixed price type
  triggerPercentage: t.bigint(), // for percentage type (in basis points)
  trailingDistance: t.bigint(), // for trailing stop (in basis points)
  highestPrice: t.bigint(), // for tracking trailing stop
  minAmountOut: t.bigint().notNull().default(0n),
  poolFee: t.integer().notNull().default(3000),
  status: t.text().notNull().default("Active"), // Active, Triggered, Executed, Paused, Cancelled
  executedAmount: t.bigint().default(0n),
  createdAt: t.bigint().notNull(),
  updatedAt: t.bigint().notNull(),
  triggeredAt: t.bigint(),
  executedAt: t.bigint(),
}));

export const stopLossExecution = onchainTable("stop_loss_execution", (t) => ({
  id: t.text().primaryKey(), // txHash-logIndex
  strategyId: t.text().notNull(),
  amountSold: t.bigint().notNull(),
  amountReceived: t.bigint().notNull(),
  executionPrice: t.bigint().notNull(),
  txHash: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  timestamp: t.bigint().notNull(),
}));

// ==================== Subscription Tables ====================

export const subscription = onchainTable("subscription", (t) => ({
  id: t.text().primaryKey(), // Subscription ID (bytes32)
  subscriberId: t.text().notNull(),
  recipientId: t.text().notNull(),
  tokenId: t.text().notNull(),
  amount: t.bigint().notNull(),
  billingPeriod: t.text().notNull(), // Daily, Weekly, Monthly, Quarterly, Yearly
  maxPayments: t.integer().notNull(),
  paymentsCompleted: t.integer().notNull().default(0),
  nextPaymentTime: t.bigint().notNull(),
  status: t.text().notNull().default("Active"), // Active, Paused, Cancelled, Expired
  totalPaid: t.bigint().notNull().default(0n),
  createdAt: t.bigint().notNull(),
  updatedAt: t.bigint().notNull(),
  cancelledAt: t.bigint(),
}));

export const payment = onchainTable("payment", (t) => ({
  id: t.text().primaryKey(), // txHash-logIndex
  subscriptionId: t.text().notNull(),
  amount: t.bigint().notNull(),
  paymentNumber: t.integer().notNull(),
  txHash: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  timestamp: t.bigint().notNull(),
}));

// ==================== Token Table ====================

export const token = onchainTable("token", (t) => ({
  id: t.text().primaryKey(), // Token address (lowercase)
  address: t.text().notNull(),
  symbol: t.text().notNull(),
  decimals: t.integer().notNull(),
}));

// ==================== Activity Log Table ====================

export const activityLog = onchainTable("activity_log", (t) => ({
  id: t.text().primaryKey(), // txHash-logIndex
  userId: t.text().notNull(),
  eventType: t.text().notNull(),
  description: t.text().notNull(),
  metadata: t.text(),
  txHash: t.text().notNull(),
  blockNumber: t.bigint().notNull(),
  timestamp: t.bigint().notNull(),
}));

// ==================== Daily Stats Table ====================

export const dailyStats = onchainTable("daily_stats", (t) => ({
  id: t.text().primaryKey(), // userId-date
  userId: t.text().notNull(),
  date: t.text().notNull(), // YYYY-MM-DD
  totalSpent: t.bigint().notNull().default(0n),
  totalReceived: t.bigint().notNull().default(0n),
  dcaExecutions: t.integer().notNull().default(0),
  subscriptionPayments: t.integer().notNull().default(0),
  subscriptionRevenue: t.bigint().notNull().default(0n),
}));

// ==================== Global Stats Table ====================

export const globalStats = onchainTable("global_stats", (t) => ({
  id: t.text().primaryKey(), // "global"
  totalUsers: t.integer().notNull().default(0),
  totalShieldsActivated: t.integer().notNull().default(0),
  totalDCAStrategies: t.integer().notNull().default(0),
  totalDCAExecutions: t.integer().notNull().default(0),
  totalDCAVolume: t.bigint().notNull().default(0n),
  totalRebalanceStrategies: t.integer().notNull().default(0),
  totalRebalanceExecutions: t.integer().notNull().default(0),
  totalRebalanceVolume: t.bigint().notNull().default(0n),
  totalStopLossStrategies: t.integer().notNull().default(0),
  totalStopLossExecutions: t.integer().notNull().default(0),
  totalStopLossVolume: t.bigint().notNull().default(0n),
  totalSubscriptions: t.integer().notNull().default(0),
  totalPayments: t.integer().notNull().default(0),
  totalPaymentVolume: t.bigint().notNull().default(0n),
  lastUpdated: t.bigint().notNull(),
}));

// ==================== Relations ====================

export const userRelations = relations(user, ({ one, many }) => ({
  shield: one(shield, { fields: [user.id], references: [shield.userId] }),
  dcaStrategies: many(dcaStrategy),
  rebalanceStrategies: many(rebalanceStrategy),
  stopLossStrategies: many(stopLossStrategy),
  subscriptions: many(subscription),
  activityLogs: many(activityLog),
}));

export const shieldRelations = relations(shield, ({ one, many }) => ({
  user: one(user, { fields: [shield.userId], references: [user.id] }),
  whitelistedContracts: many(whitelistedContract),
  spendingRecords: many(spendingRecord),
}));

export const dcaStrategyRelations = relations(dcaStrategy, ({ one, many }) => ({
  user: one(user, { fields: [dcaStrategy.userId], references: [user.id] }),
  sourceToken: one(token, { fields: [dcaStrategy.sourceTokenId], references: [token.id] }),
  targetToken: one(token, { fields: [dcaStrategy.targetTokenId], references: [token.id] }),
  executions: many(dcaExecution),
}));

export const subscriptionRelations = relations(subscription, ({ one, many }) => ({
  subscriber: one(user, { fields: [subscription.subscriberId], references: [user.id] }),
  token: one(token, { fields: [subscription.tokenId], references: [token.id] }),
  payments: many(payment),
}));

export const rebalanceStrategyRelations = relations(rebalanceStrategy, ({ one, many }) => ({
  user: one(user, { fields: [rebalanceStrategy.userId], references: [user.id] }),
  allocations: many(rebalanceAllocation),
  executions: many(rebalanceExecution),
}));

export const rebalanceAllocationRelations = relations(rebalanceAllocation, ({ one }) => ({
  strategy: one(rebalanceStrategy, { fields: [rebalanceAllocation.strategyId], references: [rebalanceStrategy.id] }),
  token: one(token, { fields: [rebalanceAllocation.tokenId], references: [token.id] }),
}));

export const rebalanceExecutionRelations = relations(rebalanceExecution, ({ one }) => ({
  strategy: one(rebalanceStrategy, { fields: [rebalanceExecution.strategyId], references: [rebalanceStrategy.id] }),
}));

export const stopLossStrategyRelations = relations(stopLossStrategy, ({ one, many }) => ({
  user: one(user, { fields: [stopLossStrategy.userId], references: [user.id] }),
  tokenToSell: one(token, { fields: [stopLossStrategy.tokenToSellId], references: [token.id] }),
  tokenToReceive: one(token, { fields: [stopLossStrategy.tokenToReceiveId], references: [token.id] }),
  executions: many(stopLossExecution),
}));

export const stopLossExecutionRelations = relations(stopLossExecution, ({ one }) => ({
  strategy: one(stopLossStrategy, { fields: [stopLossExecution.strategyId], references: [stopLossStrategy.id] }),
}));

export const activityLogRelations = relations(activityLog, ({ one }) => ({
  user: one(user, { fields: [activityLog.userId], references: [user.id] }),
}));

export const whitelistedContractRelations = relations(whitelistedContract, ({ one }) => ({
  shield: one(shield, { fields: [whitelistedContract.shieldId], references: [shield.id] }),
}));

export const spendingRecordRelations = relations(spendingRecord, ({ one }) => ({
  shield: one(shield, { fields: [spendingRecord.shieldId], references: [shield.id] }),
  token: one(token, { fields: [spendingRecord.tokenId], references: [token.id] }),
}));

export const dcaExecutionRelations = relations(dcaExecution, ({ one }) => ({
  strategy: one(dcaStrategy, { fields: [dcaExecution.strategyId], references: [dcaStrategy.id] }),
}));

export const paymentRelations = relations(payment, ({ one }) => ({
  subscription: one(subscription, { fields: [payment.subscriptionId], references: [subscription.id] }),
}));

export const dailyStatsRelations = relations(dailyStats, ({ one }) => ({
  user: one(user, { fields: [dailyStats.userId], references: [user.id] }),
}));
