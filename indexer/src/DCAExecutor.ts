import { ponder } from "ponder:registry";
import {
  user,
  dcaStrategy,
  dcaExecution,
  activityLog,
  dailyStats,
  globalStats,
  token,
} from "../ponder.schema";

// Helper to get or create user
async function getOrCreateUser(context: any, address: string, timestamp: bigint) {
  const userId = address.toLowerCase();

  let existingUser = await context.db.find(user, { id: userId });

  if (!existingUser) {
    await context.db.insert(user).values({
      id: userId,
      address: address,
      totalInvested: 0n,
      totalReceived: 0n,
      totalDCAExecutions: 0,
      totalPaymentsMade: 0,
      totalPaymentsReceived: 0,
      createdAt: timestamp,
      updatedAt: timestamp,
    });

    // Update global stats
    const stats = await context.db.find(globalStats, { id: "global" });
    if (stats) {
      await context.db.update(globalStats, { id: "global" }).set({
        totalUsers: stats.totalUsers + 1,
        lastUpdated: timestamp,
      });
    } else {
      await context.db.insert(globalStats).values({
        id: "global",
        totalUsers: 1,
        totalShieldsActivated: 0,
        totalDCAStrategies: 0,
        totalDCAExecutions: 0,
        totalDCAVolume: 0n,
        totalRebalanceStrategies: 0,
        totalRebalanceExecutions: 0,
        totalRebalanceVolume: 0n,
        totalStopLossStrategies: 0,
        totalStopLossExecutions: 0,
        totalStopLossVolume: 0n,
        totalSubscriptions: 0,
        totalPayments: 0,
        totalPaymentVolume: 0n,
        lastUpdated: timestamp,
      });
    }
  }

  return userId;
}

// Helper to get or create token
async function getOrCreateToken(context: any, address: string) {
  const tokenId = address.toLowerCase();

  let existingToken = await context.db.find(token, { id: tokenId });

  if (!existingToken) {
    // Default values, could be enhanced with token metadata lookup
    await context.db.insert(token).values({
      id: tokenId,
      address: address,
      symbol: "UNKNOWN",
      decimals: 18,
    });
  }

  return tokenId;
}

// Helper to create activity log
async function createActivityLog(
  context: any,
  userId: string,
  eventType: string,
  description: string,
  txHash: string,
  blockNumber: bigint,
  timestamp: bigint,
  metadata?: string
) {
  const logId = `${txHash}-${eventType}-${timestamp}`;

  await context.db.insert(activityLog).values({
    id: logId,
    userId,
    eventType,
    description,
    metadata: metadata || null,
    txHash,
    blockNumber,
    timestamp,
  });
}

// Helper to get date string
function getDateString(timestamp: bigint): string {
  const date = new Date(Number(timestamp) * 1000);
  return date.toISOString().split("T")[0];
}

// ==================== DCA Strategy Events ====================

ponder.on("DCAExecutor:StrategyCreated", async ({ event, context }) => {
  const userAddress = event.args.user;
  const timestamp = BigInt(event.block.timestamp);
  const strategyId = event.args.strategyId;

  // Create or get user
  const userId = await getOrCreateUser(context, userAddress, timestamp);

  // Create or get tokens
  const sourceTokenId = await getOrCreateToken(context, event.args.sourceToken);
  const targetTokenId = await getOrCreateToken(context, event.args.targetToken);

  // Calculate next execution time (first execution is immediate based on contract)
  const nextExecutionTime = timestamp;

  // Create DCA strategy
  await context.db.insert(dcaStrategy).values({
    id: strategyId,
    userId,
    sourceTokenId,
    targetTokenId,
    amountPerExecution: event.args.amountPerExecution,
    minAmountOut: 0n, // Not in event, set default
    intervalSeconds: event.args.intervalSeconds,
    totalExecutions: Number(event.args.totalExecutions),
    executionsCompleted: 0,
    status: "Active",
    totalAmountIn: 0n,
    totalAmountOut: 0n,
    averagePrice: 0n,
    lastExecutionTime: null,
    nextExecutionTime,
    autoPausedReason: null,
    createdAt: timestamp,
    updatedAt: timestamp,
  });

  // Update user stats
  await context.db.update(user, { id: userId }).set({
    updatedAt: timestamp,
  });

  // Update global stats
  const stats = await context.db.find(globalStats, { id: "global" });
  if (stats) {
    await context.db.update(globalStats, { id: "global" }).set({
      totalDCAStrategies: stats.totalDCAStrategies + 1,
      lastUpdated: timestamp,
    });
  }

  // Create activity log
  await createActivityLog(
    context,
    userId,
    "DCA_STRATEGY_CREATED",
    `DCA strategy created: ${event.args.amountPerExecution} per execution, ${event.args.totalExecutions} total executions`,
    event.transaction.hash,
    event.block.number,
    timestamp,
    JSON.stringify({
      strategyId,
      sourceToken: event.args.sourceToken,
      targetToken: event.args.targetToken,
      intervalSeconds: event.args.intervalSeconds.toString(),
    })
  );
});

ponder.on("DCAExecutor:DCAExecuted", async ({ event, context }) => {
  const strategyId = event.args.strategyId;
  const timestamp = event.args.timestamp;
  const userId = event.args.user.toLowerCase();

  // Create execution record
  const executionId = `${event.transaction.hash}-${event.log.logIndex}`;

  // Get strategy to calculate price
  const strategy = await context.db.find(dcaStrategy, { id: strategyId });
  const price = event.args.amountOut > 0n
    ? (event.args.amountIn * BigInt(1e18)) / event.args.amountOut
    : 0n;

  await context.db.insert(dcaExecution).values({
    id: executionId,
    strategyId,
    amountIn: event.args.amountIn,
    amountOut: event.args.amountOut,
    price,
    executionNumber: Number(event.args.executionNumber),
    txHash: event.transaction.hash,
    blockNumber: event.block.number,
    timestamp,
  });

  // Update strategy
  if (strategy) {
    const newTotalIn = strategy.totalAmountIn + event.args.amountIn;
    const newTotalOut = strategy.totalAmountOut + event.args.amountOut;
    const newAvgPrice = newTotalOut > 0n ? (newTotalIn * BigInt(1e18)) / newTotalOut : 0n;
    const newExecutionsCompleted = Number(event.args.executionNumber);
    const nextExecTime = timestamp + strategy.intervalSeconds;
    const isCompleted = newExecutionsCompleted >= strategy.totalExecutions;

    await context.db.update(dcaStrategy, { id: strategyId }).set({
      executionsCompleted: newExecutionsCompleted,
      totalAmountIn: newTotalIn,
      totalAmountOut: newTotalOut,
      averagePrice: newAvgPrice,
      lastExecutionTime: timestamp,
      nextExecutionTime: isCompleted ? null : nextExecTime,
      status: isCompleted ? "Completed" : "Active",
      updatedAt: timestamp,
    });
  }

  // Update user stats
  const existingUser = await context.db.find(user, { id: userId });
  if (existingUser) {
    await context.db.update(user, { id: userId }).set({
      totalInvested: existingUser.totalInvested + event.args.amountIn,
      totalDCAExecutions: existingUser.totalDCAExecutions + 1,
      updatedAt: timestamp,
    });
  }

  // Update daily stats
  const dateStr = getDateString(timestamp);
  const dailyStatsId = `${userId}-${dateStr}`;

  const existingStats = await context.db.find(dailyStats, { id: dailyStatsId });
  if (existingStats) {
    await context.db.update(dailyStats, { id: dailyStatsId }).set({
      dcaExecutions: existingStats.dcaExecutions + 1,
      totalSpent: existingStats.totalSpent + event.args.amountIn,
    });
  } else {
    await context.db.insert(dailyStats).values({
      id: dailyStatsId,
      userId,
      date: dateStr,
      totalSpent: event.args.amountIn,
      totalReceived: 0n,
      dcaExecutions: 1,
      subscriptionPayments: 0,
      subscriptionRevenue: 0n,
    });
  }

  // Update global stats
  const stats = await context.db.find(globalStats, { id: "global" });
  if (stats) {
    await context.db.update(globalStats, { id: "global" }).set({
      totalDCAExecutions: stats.totalDCAExecutions + 1,
      totalDCAVolume: stats.totalDCAVolume + event.args.amountIn,
      lastUpdated: timestamp,
    });
  }

  // Create activity log
  await createActivityLog(
    context,
    userId,
    "DCA_EXECUTED",
    `DCA execution #${event.args.executionNumber}: ${event.args.amountIn} in, ${event.args.amountOut} out`,
    event.transaction.hash,
    event.block.number,
    timestamp,
    JSON.stringify({
      strategyId,
      amountIn: event.args.amountIn.toString(),
      amountOut: event.args.amountOut.toString(),
    })
  );
});

ponder.on("DCAExecutor:StrategyPaused", async ({ event, context }) => {
  const strategyId = event.args.strategyId;
  const timestamp = event.args.timestamp;

  const strategy = await context.db.find(dcaStrategy, { id: strategyId });

  await context.db.update(dcaStrategy, { id: strategyId }).set({
    status: "Paused",
    updatedAt: timestamp,
  });

  if (strategy) {
    await createActivityLog(
      context,
      strategy.userId,
      "DCA_STRATEGY_PAUSED",
      "DCA strategy paused",
      event.transaction.hash,
      event.block.number,
      timestamp,
      JSON.stringify({ strategyId })
    );
  }
});

ponder.on("DCAExecutor:StrategyResumed", async ({ event, context }) => {
  const strategyId = event.args.strategyId;
  const timestamp = event.args.timestamp;

  const strategy = await context.db.find(dcaStrategy, { id: strategyId });

  await context.db.update(dcaStrategy, { id: strategyId }).set({
    status: "Active",
    autoPausedReason: null,
    updatedAt: timestamp,
  });

  if (strategy) {
    await createActivityLog(
      context,
      strategy.userId,
      "DCA_STRATEGY_RESUMED",
      "DCA strategy resumed",
      event.transaction.hash,
      event.block.number,
      timestamp,
      JSON.stringify({ strategyId })
    );
  }
});

ponder.on("DCAExecutor:StrategyCancelled", async ({ event, context }) => {
  const strategyId = event.args.strategyId;
  const timestamp = event.args.timestamp;

  const strategy = await context.db.find(dcaStrategy, { id: strategyId });

  await context.db.update(dcaStrategy, { id: strategyId }).set({
    status: "Cancelled",
    nextExecutionTime: null,
    updatedAt: timestamp,
  });

  if (strategy) {
    await createActivityLog(
      context,
      strategy.userId,
      "DCA_STRATEGY_CANCELLED",
      "DCA strategy cancelled",
      event.transaction.hash,
      event.block.number,
      timestamp,
      JSON.stringify({ strategyId })
    );
  }
});

ponder.on("DCAExecutor:StrategyCompleted", async ({ event, context }) => {
  const strategyId = event.args.strategyId;
  const timestamp = BigInt(event.block.timestamp);

  const strategy = await context.db.find(dcaStrategy, { id: strategyId });

  await context.db.update(dcaStrategy, { id: strategyId }).set({
    status: "Completed",
    totalAmountIn: event.args.totalAmountIn,
    totalAmountOut: event.args.totalAmountOut,
    nextExecutionTime: null,
    updatedAt: timestamp,
  });

  if (strategy) {
    await createActivityLog(
      context,
      strategy.userId,
      "DCA_STRATEGY_COMPLETED",
      `DCA strategy completed: total in ${event.args.totalAmountIn}, total out ${event.args.totalAmountOut}`,
      event.transaction.hash,
      event.block.number,
      timestamp,
      JSON.stringify({
        strategyId,
        totalAmountIn: event.args.totalAmountIn.toString(),
        totalAmountOut: event.args.totalAmountOut.toString(),
      })
    );
  }
});

ponder.on("DCAExecutor:StrategyUpdated", async ({ event, context }) => {
  const strategyId = event.args.strategyId;
  const timestamp = BigInt(event.block.timestamp);

  const strategy = await context.db.find(dcaStrategy, { id: strategyId });

  await context.db.update(dcaStrategy, { id: strategyId }).set({
    amountPerExecution: event.args.newAmountPerExecution,
    minAmountOut: event.args.newMinAmountOut,
    updatedAt: timestamp,
  });

  if (strategy) {
    await createActivityLog(
      context,
      strategy.userId,
      "DCA_STRATEGY_UPDATED",
      `DCA strategy updated: new amount ${event.args.newAmountPerExecution}`,
      event.transaction.hash,
      event.block.number,
      timestamp,
      JSON.stringify({
        strategyId,
        newAmountPerExecution: event.args.newAmountPerExecution.toString(),
        newMinAmountOut: event.args.newMinAmountOut.toString(),
      })
    );
  }
});

ponder.on("DCAExecutor:StrategyAutoPaused", async ({ event, context }) => {
  const strategyId = event.args.strategyId;
  const timestamp = BigInt(event.block.timestamp);

  const strategy = await context.db.find(dcaStrategy, { id: strategyId });

  await context.db.update(dcaStrategy, { id: strategyId }).set({
    status: "AutoPaused",
    autoPausedReason: event.args.reason,
    updatedAt: timestamp,
  });

  if (strategy) {
    await createActivityLog(
      context,
      strategy.userId,
      "DCA_STRATEGY_AUTO_PAUSED",
      `DCA strategy auto-paused: ${event.args.reason}`,
      event.transaction.hash,
      event.block.number,
      timestamp,
      JSON.stringify({
        strategyId,
        reason: event.args.reason,
        avgPrice: event.args.avgPrice.toString(),
        currentPrice: event.args.currentPrice.toString(),
        deviation: event.args.deviation.toString(),
      })
    );
  }
});
