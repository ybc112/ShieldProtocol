import { ponder } from "ponder:registry";
import {
  user,
  rebalanceStrategy,
  rebalanceAllocation,
  rebalanceExecution,
  activityLog,
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
  metadata: any,
  txHash: string,
  blockNumber: bigint,
  timestamp: bigint,
  logIndex: number
) {
  const activityId = `${txHash}-${logIndex}`;

  await context.db.insert(activityLog).values({
    id: activityId,
    userId,
    eventType,
    description,
    metadata: JSON.stringify(metadata),
    txHash,
    blockNumber,
    timestamp,
  });
}

// ============ Event Handlers ============

// Handle Strategy Created
ponder.on("RebalanceExecutor:StrategyCreated", async ({ event, context }) => {
  const { strategyId, user: userAddress, tokens, targetWeights, rebalanceThreshold } = event.args;
  const timestamp = BigInt(event.block.timestamp);
  const txHash = event.transaction.hash;
  const blockNumber = BigInt(event.block.number);
  const logIndex = event.log.logIndex;

  // Get or create user
  const userId = await getOrCreateUser(context, userAddress, timestamp);

  // Create strategy
  await context.db.insert(rebalanceStrategy).values({
    id: strategyId,
    userId,
    rebalanceThreshold,
    minRebalanceInterval: 0n, // Will be set via additional event or default
    lastRebalanceTime: null,
    totalRebalances: 0,
    totalValue: 0n,
    poolFee: 3000,
    status: "Active",
    createdAt: timestamp,
    updatedAt: timestamp,
  });

  // Create allocations for each token
  for (let i = 0; i < tokens.length; i++) {
    const tokenAddress = tokens[i];
    const targetWeight = targetWeights[i];

    const tokenId = await getOrCreateToken(context, tokenAddress);
    const allocationId = `${strategyId}-${tokenId}`;

    await context.db.insert(rebalanceAllocation).values({
      id: allocationId,
      strategyId,
      tokenId,
      targetWeight,
      currentWeight: 0n,
      createdAt: timestamp,
      updatedAt: timestamp,
    });
  }

  // Update global stats
  const stats = await context.db.find(globalStats, { id: "global" });
  if (stats) {
    await context.db.update(globalStats, { id: "global" }).set({
      totalRebalanceStrategies: stats.totalRebalanceStrategies + 1,
      lastUpdated: timestamp,
    });
  }

  // Create activity log
  await createActivityLog(
    context,
    userId,
    "REBALANCE_STRATEGY_CREATED",
    `Created rebalance strategy with ${tokens.length} tokens`,
    { strategyId, tokens, targetWeights: targetWeights.map(w => w.toString()), threshold: rebalanceThreshold.toString() },
    txHash,
    blockNumber,
    timestamp,
    logIndex
  );
});

// Handle Rebalance Executed
ponder.on("RebalanceExecutor:RebalanceExecuted", async ({ event, context }) => {
  const { strategyId, user: userAddress, totalValue, rebalanceNumber, timestamp: eventTimestamp } = event.args;
  const timestamp = BigInt(event.block.timestamp);
  const txHash = event.transaction.hash;
  const blockNumber = BigInt(event.block.number);
  const logIndex = event.log.logIndex;

  const userId = userAddress.toLowerCase();
  const executionId = `${txHash}-${logIndex}`;

  // Create execution record
  await context.db.insert(rebalanceExecution).values({
    id: executionId,
    strategyId,
    totalValue,
    rebalanceNumber: Number(rebalanceNumber),
    txHash,
    blockNumber,
    timestamp,
  });

  // Update strategy
  const strategy = await context.db.find(rebalanceStrategy, { id: strategyId });
  if (strategy) {
    await context.db.update(rebalanceStrategy, { id: strategyId }).set({
      totalRebalances: strategy.totalRebalances + 1,
      totalValue,
      lastRebalanceTime: timestamp,
      updatedAt: timestamp,
    });
  }

  // Update global stats
  const stats = await context.db.find(globalStats, { id: "global" });
  if (stats) {
    await context.db.update(globalStats, { id: "global" }).set({
      totalRebalanceExecutions: stats.totalRebalanceExecutions + 1,
      totalRebalanceVolume: stats.totalRebalanceVolume + totalValue,
      lastUpdated: timestamp,
    });
  }

  // Create activity log
  await createActivityLog(
    context,
    userId,
    "REBALANCE_EXECUTED",
    `Executed rebalance #${rebalanceNumber}`,
    { strategyId, totalValue: totalValue.toString(), rebalanceNumber: Number(rebalanceNumber) },
    txHash,
    blockNumber,
    timestamp,
    logIndex
  );
});

// Handle Strategy Paused
ponder.on("RebalanceExecutor:StrategyPaused", async ({ event, context }) => {
  const { strategyId, timestamp: eventTimestamp } = event.args;
  const timestamp = BigInt(event.block.timestamp);
  const txHash = event.transaction.hash;
  const blockNumber = BigInt(event.block.number);
  const logIndex = event.log.logIndex;

  const strategy = await context.db.find(rebalanceStrategy, { id: strategyId });
  if (strategy) {
    await context.db.update(rebalanceStrategy, { id: strategyId }).set({
      status: "Paused",
      updatedAt: timestamp,
    });

    // Create activity log
    await createActivityLog(
      context,
      strategy.userId,
      "REBALANCE_STRATEGY_PAUSED",
      "Rebalance strategy paused",
      { strategyId },
      txHash,
      blockNumber,
      timestamp,
      logIndex
    );
  }
});

// Handle Strategy Resumed
ponder.on("RebalanceExecutor:StrategyResumed", async ({ event, context }) => {
  const { strategyId, timestamp: eventTimestamp } = event.args;
  const timestamp = BigInt(event.block.timestamp);
  const txHash = event.transaction.hash;
  const blockNumber = BigInt(event.block.number);
  const logIndex = event.log.logIndex;

  const strategy = await context.db.find(rebalanceStrategy, { id: strategyId });
  if (strategy) {
    await context.db.update(rebalanceStrategy, { id: strategyId }).set({
      status: "Active",
      updatedAt: timestamp,
    });

    // Create activity log
    await createActivityLog(
      context,
      strategy.userId,
      "REBALANCE_STRATEGY_RESUMED",
      "Rebalance strategy resumed",
      { strategyId },
      txHash,
      blockNumber,
      timestamp,
      logIndex
    );
  }
});

// Handle Strategy Cancelled
ponder.on("RebalanceExecutor:StrategyCancelled", async ({ event, context }) => {
  const { strategyId, timestamp: eventTimestamp } = event.args;
  const timestamp = BigInt(event.block.timestamp);
  const txHash = event.transaction.hash;
  const blockNumber = BigInt(event.block.number);
  const logIndex = event.log.logIndex;

  const strategy = await context.db.find(rebalanceStrategy, { id: strategyId });
  if (strategy) {
    await context.db.update(rebalanceStrategy, { id: strategyId }).set({
      status: "Cancelled",
      updatedAt: timestamp,
    });

    // Create activity log
    await createActivityLog(
      context,
      strategy.userId,
      "REBALANCE_STRATEGY_CANCELLED",
      "Rebalance strategy cancelled",
      { strategyId },
      txHash,
      blockNumber,
      timestamp,
      logIndex
    );
  }
});

// Handle Allocation Updated
ponder.on("RebalanceExecutor:AllocationUpdated", async ({ event, context }) => {
  const { strategyId, token: tokenAddress, oldWeight, newWeight } = event.args;
  const timestamp = BigInt(event.block.timestamp);

  const tokenId = tokenAddress.toLowerCase();
  const allocationId = `${strategyId}-${tokenId}`;

  const allocation = await context.db.find(rebalanceAllocation, { id: allocationId });
  if (allocation) {
    await context.db.update(rebalanceAllocation, { id: allocationId }).set({
      targetWeight: newWeight,
      updatedAt: timestamp,
    });
  }

  // Update strategy timestamp
  await context.db.update(rebalanceStrategy, { id: strategyId }).set({
    updatedAt: timestamp,
  });
});

// Handle Threshold Updated
ponder.on("RebalanceExecutor:ThresholdUpdated", async ({ event, context }) => {
  const { strategyId, oldThreshold, newThreshold } = event.args;
  const timestamp = BigInt(event.block.timestamp);

  const strategy = await context.db.find(rebalanceStrategy, { id: strategyId });
  if (strategy) {
    await context.db.update(rebalanceStrategy, { id: strategyId }).set({
      rebalanceThreshold: newThreshold,
      updatedAt: timestamp,
    });
  }
});
