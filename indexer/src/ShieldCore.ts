import { ponder } from "ponder:registry";
import {
  user,
  shield,
  whitelistedContract,
  spendingRecord,
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

// ==================== Shield Events ====================

ponder.on("ShieldCore:ShieldActivated", async ({ event, context }) => {
  const userAddress = event.args.user;
  const timestamp = event.args.timestamp;

  // Create or get user
  const userId = await getOrCreateUser(context, userAddress, timestamp);

  // Create shield
  await context.db.insert(shield).values({
    id: userId,
    userId,
    dailySpendLimit: event.args.dailyLimit,
    singleTxLimit: event.args.singleTxLimit,
    spentToday: 0n,
    lastResetTimestamp: timestamp,
    isActive: true,
    emergencyMode: false,
    activatedAt: timestamp,
    updatedAt: timestamp,
  });

  // Update global stats
  const stats = await context.db.find(globalStats, { id: "global" });
  if (stats) {
    await context.db.update(globalStats, { id: "global" }).set({
      totalShieldsActivated: stats.totalShieldsActivated + 1,
      lastUpdated: timestamp,
    });
  }

  // Create activity log
  await createActivityLog(
    context,
    userId,
    "SHIELD_ACTIVATED",
    `Shield activated with daily limit: ${event.args.dailyLimit}`,
    event.transaction.hash,
    event.block.number,
    timestamp
  );
});

ponder.on("ShieldCore:ShieldConfigUpdated", async ({ event, context }) => {
  const userId = event.args.user.toLowerCase();
  const timestamp = BigInt(event.block.timestamp);

  await context.db.update(shield, { id: userId }).set({
    dailySpendLimit: event.args.newDailyLimit,
    singleTxLimit: event.args.newSingleTxLimit,
    updatedAt: timestamp,
  });

  await createActivityLog(
    context,
    userId,
    "SHIELD_CONFIG_UPDATED",
    `Shield config updated: daily limit ${event.args.newDailyLimit}, single tx limit ${event.args.newSingleTxLimit}`,
    event.transaction.hash,
    event.block.number,
    timestamp
  );
});

ponder.on("ShieldCore:ShieldDeactivated", async ({ event, context }) => {
  const userId = event.args.user.toLowerCase();
  const timestamp = event.args.timestamp;

  await context.db.update(shield, { id: userId }).set({
    isActive: false,
    updatedAt: timestamp,
  });

  await createActivityLog(
    context,
    userId,
    "SHIELD_DEACTIVATED",
    "Shield protection deactivated",
    event.transaction.hash,
    event.block.number,
    timestamp
  );
});

ponder.on("ShieldCore:EmergencyModeEnabled", async ({ event, context }) => {
  const userId = event.args.user.toLowerCase();
  const timestamp = event.args.timestamp;

  await context.db.update(shield, { id: userId }).set({
    emergencyMode: true,
    updatedAt: timestamp,
  });

  await createActivityLog(
    context,
    userId,
    "EMERGENCY_MODE_ENABLED",
    "Emergency mode enabled - all transactions blocked",
    event.transaction.hash,
    event.block.number,
    timestamp
  );
});

ponder.on("ShieldCore:EmergencyModeDisabled", async ({ event, context }) => {
  const userId = event.args.user.toLowerCase();
  const timestamp = event.args.timestamp;

  await context.db.update(shield, { id: userId }).set({
    emergencyMode: false,
    updatedAt: timestamp,
  });

  await createActivityLog(
    context,
    userId,
    "EMERGENCY_MODE_DISABLED",
    "Emergency mode disabled - normal operations resumed",
    event.transaction.hash,
    event.block.number,
    timestamp
  );
});

ponder.on("ShieldCore:SpendingRecorded", async ({ event, context }) => {
  const userId = event.args.user.toLowerCase();
  const tokenAddress = event.args.token.toLowerCase();
  const timestamp = event.args.timestamp;

  // Create spending record
  const recordId = `${event.transaction.hash}-${event.log.logIndex}`;
  await context.db.insert(spendingRecord).values({
    id: recordId,
    shieldId: userId,
    tokenId: tokenAddress,
    amount: event.args.amount,
    newDailyTotal: event.args.dailyTotal,
    txHash: event.transaction.hash,
    timestamp,
  });

  // Update shield spent today
  await context.db.update(shield, { id: userId }).set({
    spentToday: event.args.dailyTotal,
    updatedAt: timestamp,
  });

  // Update daily stats
  const dateStr = getDateString(timestamp);
  const dailyStatsId = `${userId}-${dateStr}`;

  const existingStats = await context.db.find(dailyStats, { id: dailyStatsId });
  if (existingStats) {
    await context.db.update(dailyStats, { id: dailyStatsId }).set({
      totalSpent: existingStats.totalSpent + event.args.amount,
    });
  } else {
    await context.db.insert(dailyStats).values({
      id: dailyStatsId,
      userId,
      date: dateStr,
      totalSpent: event.args.amount,
      totalReceived: 0n,
      dcaExecutions: 0,
      subscriptionPayments: 0,
      subscriptionRevenue: 0n,
    });
  }
});

ponder.on("ShieldCore:ContractWhitelisted", async ({ event, context }) => {
  const userId = event.args.user.toLowerCase();
  const contractAddress = event.args.contractAddress.toLowerCase();
  const timestamp = BigInt(event.block.timestamp);

  const whitelistId = `${userId}-${contractAddress}`;

  await context.db.insert(whitelistedContract).values({
    id: whitelistId,
    shieldId: userId,
    contractAddress,
    addedAt: timestamp,
    isActive: true,
  });

  await createActivityLog(
    context,
    userId,
    "CONTRACT_WHITELISTED",
    `Contract ${contractAddress} added to whitelist`,
    event.transaction.hash,
    event.block.number,
    timestamp
  );
});

ponder.on("ShieldCore:ContractRemovedFromWhitelist", async ({ event, context }) => {
  const userId = event.args.user.toLowerCase();
  const contractAddress = event.args.contractAddress.toLowerCase();
  const timestamp = BigInt(event.block.timestamp);

  const whitelistId = `${userId}-${contractAddress}`;

  await context.db.update(whitelistedContract, { id: whitelistId }).set({
    isActive: false,
  });

  await createActivityLog(
    context,
    userId,
    "CONTRACT_REMOVED_FROM_WHITELIST",
    `Contract ${contractAddress} removed from whitelist`,
    event.transaction.hash,
    event.block.number,
    timestamp
  );
});

ponder.on("ShieldCore:DailyLimitReset", async ({ event, context }) => {
  const userId = event.args.user.toLowerCase();
  const timestamp = event.args.timestamp;

  await context.db.update(shield, { id: userId }).set({
    spentToday: 0n,
    lastResetTimestamp: timestamp,
    updatedAt: timestamp,
  });
});
