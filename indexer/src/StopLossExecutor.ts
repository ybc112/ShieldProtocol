import { ponder } from "ponder:registry";
import {
  user,
  stopLossStrategy,
  stopLossExecution,
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

// Stop-loss type mapping
const STOP_LOSS_TYPES = ["FixedPrice", "Percentage", "TrailingStop"];

// ============ Event Handlers ============

// Handle Strategy Created
ponder.on("StopLossExecutor:StrategyCreated", async ({ event, context }) => {
  const { strategyId, user: userAddress, tokenToSell, tokenToReceive, amount, stopLossType, triggerValue } = event.args;
  const timestamp = BigInt(event.block.timestamp);
  const txHash = event.transaction.hash;
  const blockNumber = BigInt(event.block.number);
  const logIndex = event.log.logIndex;

  // Get or create user
  const userId = await getOrCreateUser(context, userAddress, timestamp);

  // Get or create tokens
  const tokenToSellId = await getOrCreateToken(context, tokenToSell);
  const tokenToReceiveId = await getOrCreateToken(context, tokenToReceive);

  // Determine trigger values based on type
  let triggerPrice: bigint | null = null;
  let triggerPercentage: bigint | null = null;

  if (stopLossType === 0) {
    // FixedPrice
    triggerPrice = triggerValue;
  } else {
    // Percentage or TrailingStop
    triggerPercentage = triggerValue;
  }

  // Create strategy
  await context.db.insert(stopLossStrategy).values({
    id: strategyId,
    userId,
    tokenToSellId,
    tokenToReceiveId,
    amount,
    stopLossType,
    triggerPrice,
    triggerPercentage,
    trailingDistance: null,
    highestPrice: null,
    minAmountOut: 0n,
    poolFee: 3000,
    status: "Active",
    executedAmount: 0n,
    createdAt: timestamp,
    updatedAt: timestamp,
    triggeredAt: null,
    executedAt: null,
  });

  // Update global stats
  const stats = await context.db.find(globalStats, { id: "global" });
  if (stats) {
    await context.db.update(globalStats, { id: "global" }).set({
      totalStopLossStrategies: stats.totalStopLossStrategies + 1,
      lastUpdated: timestamp,
    });
  }

  // Create activity log
  await createActivityLog(
    context,
    userId,
    "STOP_LOSS_STRATEGY_CREATED",
    `Created ${STOP_LOSS_TYPES[stopLossType]} stop-loss strategy`,
    {
      strategyId,
      tokenToSell,
      tokenToReceive,
      amount: amount.toString(),
      stopLossType: STOP_LOSS_TYPES[stopLossType],
      triggerValue: triggerValue.toString()
    },
    txHash,
    blockNumber,
    timestamp,
    logIndex
  );
});

// Handle Stop Loss Triggered
ponder.on("StopLossExecutor:StopLossTriggered", async ({ event, context }) => {
  const { strategyId, user: userAddress, currentPrice, triggerPrice, timestamp: eventTimestamp } = event.args;
  const timestamp = BigInt(event.block.timestamp);
  const txHash = event.transaction.hash;
  const blockNumber = BigInt(event.block.number);
  const logIndex = event.log.logIndex;

  const userId = userAddress.toLowerCase();

  // Update strategy status
  const strategy = await context.db.find(stopLossStrategy, { id: strategyId });
  if (strategy) {
    await context.db.update(stopLossStrategy, { id: strategyId }).set({
      status: "Triggered",
      triggeredAt: timestamp,
      updatedAt: timestamp,
    });
  }

  // Create activity log
  await createActivityLog(
    context,
    userId,
    "STOP_LOSS_TRIGGERED",
    `Stop-loss triggered at price ${currentPrice}`,
    { strategyId, currentPrice: currentPrice.toString(), triggerPrice: triggerPrice.toString() },
    txHash,
    blockNumber,
    timestamp,
    logIndex
  );
});

// Handle Stop Loss Executed
ponder.on("StopLossExecutor:StopLossExecuted", async ({ event, context }) => {
  const { strategyId, user: userAddress, amountSold, amountReceived, executionPrice, timestamp: eventTimestamp } = event.args;
  const timestamp = BigInt(event.block.timestamp);
  const txHash = event.transaction.hash;
  const blockNumber = BigInt(event.block.number);
  const logIndex = event.log.logIndex;

  const userId = userAddress.toLowerCase();
  const executionId = `${txHash}-${logIndex}`;

  // Create execution record
  await context.db.insert(stopLossExecution).values({
    id: executionId,
    strategyId,
    amountSold,
    amountReceived,
    executionPrice,
    txHash,
    blockNumber,
    timestamp,
  });

  // Update strategy status
  const strategy = await context.db.find(stopLossStrategy, { id: strategyId });
  if (strategy) {
    await context.db.update(stopLossStrategy, { id: strategyId }).set({
      status: "Executed",
      executedAmount: amountSold,
      executedAt: timestamp,
      updatedAt: timestamp,
    });
  }

  // Update global stats
  const stats = await context.db.find(globalStats, { id: "global" });
  if (stats) {
    await context.db.update(globalStats, { id: "global" }).set({
      totalStopLossExecutions: stats.totalStopLossExecutions + 1,
      totalStopLossVolume: stats.totalStopLossVolume + amountSold,
      lastUpdated: timestamp,
    });
  }

  // Create activity log
  await createActivityLog(
    context,
    userId,
    "STOP_LOSS_EXECUTED",
    `Stop-loss executed: sold ${amountSold} for ${amountReceived}`,
    {
      strategyId,
      amountSold: amountSold.toString(),
      amountReceived: amountReceived.toString(),
      executionPrice: executionPrice.toString()
    },
    txHash,
    blockNumber,
    timestamp,
    logIndex
  );
});

// Handle Strategy Paused
ponder.on("StopLossExecutor:StrategyPaused", async ({ event, context }) => {
  const { strategyId, timestamp: eventTimestamp } = event.args;
  const timestamp = BigInt(event.block.timestamp);
  const txHash = event.transaction.hash;
  const blockNumber = BigInt(event.block.number);
  const logIndex = event.log.logIndex;

  const strategy = await context.db.find(stopLossStrategy, { id: strategyId });
  if (strategy) {
    await context.db.update(stopLossStrategy, { id: strategyId }).set({
      status: "Paused",
      updatedAt: timestamp,
    });

    // Create activity log
    await createActivityLog(
      context,
      strategy.userId,
      "STOP_LOSS_STRATEGY_PAUSED",
      "Stop-loss strategy paused",
      { strategyId },
      txHash,
      blockNumber,
      timestamp,
      logIndex
    );
  }
});

// Handle Strategy Resumed
ponder.on("StopLossExecutor:StrategyResumed", async ({ event, context }) => {
  const { strategyId, timestamp: eventTimestamp } = event.args;
  const timestamp = BigInt(event.block.timestamp);
  const txHash = event.transaction.hash;
  const blockNumber = BigInt(event.block.number);
  const logIndex = event.log.logIndex;

  const strategy = await context.db.find(stopLossStrategy, { id: strategyId });
  if (strategy) {
    await context.db.update(stopLossStrategy, { id: strategyId }).set({
      status: "Active",
      updatedAt: timestamp,
    });

    // Create activity log
    await createActivityLog(
      context,
      strategy.userId,
      "STOP_LOSS_STRATEGY_RESUMED",
      "Stop-loss strategy resumed",
      { strategyId },
      txHash,
      blockNumber,
      timestamp,
      logIndex
    );
  }
});

// Handle Strategy Cancelled
ponder.on("StopLossExecutor:StrategyCancelled", async ({ event, context }) => {
  const { strategyId, timestamp: eventTimestamp } = event.args;
  const timestamp = BigInt(event.block.timestamp);
  const txHash = event.transaction.hash;
  const blockNumber = BigInt(event.block.number);
  const logIndex = event.log.logIndex;

  const strategy = await context.db.find(stopLossStrategy, { id: strategyId });
  if (strategy) {
    await context.db.update(stopLossStrategy, { id: strategyId }).set({
      status: "Cancelled",
      updatedAt: timestamp,
    });

    // Create activity log
    await createActivityLog(
      context,
      strategy.userId,
      "STOP_LOSS_STRATEGY_CANCELLED",
      "Stop-loss strategy cancelled",
      { strategyId },
      txHash,
      blockNumber,
      timestamp,
      logIndex
    );
  }
});

// Handle Strategy Updated
ponder.on("StopLossExecutor:StrategyUpdated", async ({ event, context }) => {
  const { strategyId, newTriggerValue, newMinAmountOut } = event.args;
  const timestamp = BigInt(event.block.timestamp);
  const txHash = event.transaction.hash;
  const blockNumber = BigInt(event.block.number);
  const logIndex = event.log.logIndex;

  const strategy = await context.db.find(stopLossStrategy, { id: strategyId });
  if (strategy) {
    // Determine what to update based on stop loss type
    const updates: any = {
      minAmountOut: newMinAmountOut,
      updatedAt: timestamp,
    };

    if (strategy.stopLossType === 0) {
      // FixedPrice
      updates.triggerPrice = newTriggerValue;
    } else {
      // Percentage or TrailingStop
      updates.triggerPercentage = newTriggerValue;
    }

    await context.db.update(stopLossStrategy, { id: strategyId }).set(updates);

    // Create activity log
    await createActivityLog(
      context,
      strategy.userId,
      "STOP_LOSS_STRATEGY_UPDATED",
      "Stop-loss strategy parameters updated",
      { strategyId, newTriggerValue: newTriggerValue.toString(), newMinAmountOut: newMinAmountOut.toString() },
      txHash,
      blockNumber,
      timestamp,
      logIndex
    );
  }
});

// Handle Highest Price Updated (for trailing stop)
ponder.on("StopLossExecutor:HighestPriceUpdated", async ({ event, context }) => {
  const { strategyId, newHighestPrice, timestamp: eventTimestamp } = event.args;
  const timestamp = BigInt(event.block.timestamp);

  const strategy = await context.db.find(stopLossStrategy, { id: strategyId });
  if (strategy) {
    await context.db.update(stopLossStrategy, { id: strategyId }).set({
      highestPrice: newHighestPrice,
      updatedAt: timestamp,
    });
  }
});
