import { ponder } from "ponder:registry";
import {
  user,
  subscription,
  payment,
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

// Billing period enum mapping
const BILLING_PERIODS = ["Daily", "Weekly", "Monthly", "Yearly"];

function getBillingPeriodString(period: number): string {
  return BILLING_PERIODS[period] || "Unknown";
}

function getBillingPeriodSeconds(period: number): bigint {
  switch (period) {
    case 0: return BigInt(86400);      // Daily
    case 1: return BigInt(604800);     // Weekly
    case 2: return BigInt(2592000);    // Monthly (30 days)
    case 3: return BigInt(31536000);   // Yearly
    default: return BigInt(2592000);
  }
}

// ==================== Subscription Events ====================

ponder.on("SubscriptionManager:SubscriptionCreated", async ({ event, context }) => {
  const subscriberAddress = event.args.subscriber;
  const recipientAddress = event.args.recipient;
  const timestamp = BigInt(event.block.timestamp);
  const subscriptionId = event.args.subscriptionId;

  // Create or get users
  const subscriberId = await getOrCreateUser(context, subscriberAddress, timestamp);
  const recipientId = await getOrCreateUser(context, recipientAddress, timestamp);

  // Create or get token
  const tokenId = await getOrCreateToken(context, event.args.token);

  // Calculate next payment time
  const billingPeriodSeconds = getBillingPeriodSeconds(event.args.billingPeriod);
  const nextPaymentTime = timestamp + billingPeriodSeconds;

  // Create subscription
  await context.db.insert(subscription).values({
    id: subscriptionId,
    subscriberId,
    recipientId,
    tokenId,
    amount: event.args.amount,
    billingPeriod: getBillingPeriodString(event.args.billingPeriod),
    maxPayments: 0, // Not in event, default to unlimited
    paymentsCompleted: 0,
    nextPaymentTime,
    status: "Active",
    totalPaid: 0n,
    createdAt: timestamp,
    updatedAt: timestamp,
    cancelledAt: null,
  });

  // Update global stats
  const stats = await context.db.find(globalStats, { id: "global" });
  if (stats) {
    await context.db.update(globalStats, { id: "global" }).set({
      totalSubscriptions: stats.totalSubscriptions + 1,
      lastUpdated: timestamp,
    });
  }

  // Create activity log
  await createActivityLog(
    context,
    subscriberId,
    "SUBSCRIPTION_CREATED",
    `Subscription created: ${event.args.amount} ${getBillingPeriodString(event.args.billingPeriod)}`,
    event.transaction.hash,
    event.block.number,
    timestamp,
    JSON.stringify({
      subscriptionId,
      recipient: recipientAddress,
      token: event.args.token,
      amount: event.args.amount.toString(),
    })
  );
});

ponder.on("SubscriptionManager:PaymentExecuted", async ({ event, context }) => {
  const subscriptionId = event.args.subscriptionId;
  const subscriberId = event.args.subscriber.toLowerCase();
  const recipientId = event.args.recipient.toLowerCase();
  const timestamp = event.args.timestamp;

  // Create payment record
  const paymentId = `${event.transaction.hash}-${event.log.logIndex}`;

  await context.db.insert(payment).values({
    id: paymentId,
    subscriptionId,
    amount: event.args.amount,
    paymentNumber: Number(event.args.paymentNumber),
    txHash: event.transaction.hash,
    blockNumber: event.block.number,
    timestamp,
  });

  // Update subscription
  const sub = await context.db.find(subscription, { id: subscriptionId });
  if (sub) {
    const billingPeriodSeconds = getBillingPeriodSeconds(
      BILLING_PERIODS.indexOf(sub.billingPeriod)
    );
    const nextPaymentTime = timestamp + billingPeriodSeconds;

    const isExpired = sub.maxPayments > 0 && Number(event.args.paymentNumber) >= sub.maxPayments;

    await context.db.update(subscription, { id: subscriptionId }).set({
      paymentsCompleted: Number(event.args.paymentNumber),
      totalPaid: sub.totalPaid + event.args.amount,
      nextPaymentTime: isExpired ? timestamp : nextPaymentTime,
      status: isExpired ? "Expired" : "Active",
      updatedAt: timestamp,
    });
  }

  // Update subscriber stats
  const subscriber = await context.db.find(user, { id: subscriberId });
  if (subscriber) {
    await context.db.update(user, { id: subscriberId }).set({
      totalPaymentsMade: subscriber.totalPaymentsMade + 1,
      updatedAt: timestamp,
    });
  }

  // Update recipient stats
  const recipient = await context.db.find(user, { id: recipientId });
  if (recipient) {
    await context.db.update(user, { id: recipientId }).set({
      totalPaymentsReceived: recipient.totalPaymentsReceived + 1,
      totalReceived: recipient.totalReceived + event.args.amount,
      updatedAt: timestamp,
    });
  }

  // Update daily stats for subscriber
  const dateStr = getDateString(timestamp);
  const subscriberDailyId = `${subscriberId}-${dateStr}`;

  const subscriberStats = await context.db.find(dailyStats, { id: subscriberDailyId });
  if (subscriberStats) {
    await context.db.update(dailyStats, { id: subscriberDailyId }).set({
      subscriptionPayments: subscriberStats.subscriptionPayments + 1,
      totalSpent: subscriberStats.totalSpent + event.args.amount,
    });
  } else {
    await context.db.insert(dailyStats).values({
      id: subscriberDailyId,
      userId: subscriberId,
      date: dateStr,
      totalSpent: event.args.amount,
      totalReceived: 0n,
      dcaExecutions: 0,
      subscriptionPayments: 1,
      subscriptionRevenue: 0n,
    });
  }

  // Update daily stats for recipient
  const recipientDailyId = `${recipientId}-${dateStr}`;

  const recipientStats = await context.db.find(dailyStats, { id: recipientDailyId });
  if (recipientStats) {
    await context.db.update(dailyStats, { id: recipientDailyId }).set({
      subscriptionRevenue: recipientStats.subscriptionRevenue + event.args.amount,
      totalReceived: recipientStats.totalReceived + event.args.amount,
    });
  } else {
    await context.db.insert(dailyStats).values({
      id: recipientDailyId,
      userId: recipientId,
      date: dateStr,
      totalSpent: 0n,
      totalReceived: event.args.amount,
      dcaExecutions: 0,
      subscriptionPayments: 0,
      subscriptionRevenue: event.args.amount,
    });
  }

  // Update global stats
  const stats = await context.db.find(globalStats, { id: "global" });
  if (stats) {
    await context.db.update(globalStats, { id: "global" }).set({
      totalPayments: stats.totalPayments + 1,
      totalPaymentVolume: stats.totalPaymentVolume + event.args.amount,
      lastUpdated: timestamp,
    });
  }

  // Create activity log
  await createActivityLog(
    context,
    subscriberId,
    "SUBSCRIPTION_PAYMENT",
    `Subscription payment #${event.args.paymentNumber}: ${event.args.amount}`,
    event.transaction.hash,
    event.block.number,
    timestamp,
    JSON.stringify({
      subscriptionId,
      recipient: recipientId,
      paymentNumber: event.args.paymentNumber.toString(),
    })
  );
});

ponder.on("SubscriptionManager:SubscriptionPaused", async ({ event, context }) => {
  const subscriptionId = event.args.subscriptionId;
  const timestamp = event.args.timestamp;

  const sub = await context.db.find(subscription, { id: subscriptionId });

  await context.db.update(subscription, { id: subscriptionId }).set({
    status: "Paused",
    updatedAt: timestamp,
  });

  if (sub) {
    await createActivityLog(
      context,
      sub.subscriberId,
      "SUBSCRIPTION_PAUSED",
      "Subscription paused",
      event.transaction.hash,
      event.block.number,
      timestamp,
      JSON.stringify({ subscriptionId })
    );
  }
});

ponder.on("SubscriptionManager:SubscriptionResumed", async ({ event, context }) => {
  const subscriptionId = event.args.subscriptionId;
  const timestamp = event.args.timestamp;

  const sub = await context.db.find(subscription, { id: subscriptionId });

  if (sub) {
    const billingPeriodSeconds = getBillingPeriodSeconds(
      BILLING_PERIODS.indexOf(sub.billingPeriod)
    );
    const nextPaymentTime = timestamp + billingPeriodSeconds;

    await context.db.update(subscription, { id: subscriptionId }).set({
      status: "Active",
      nextPaymentTime,
      updatedAt: timestamp,
    });

    await createActivityLog(
      context,
      sub.subscriberId,
      "SUBSCRIPTION_RESUMED",
      "Subscription resumed",
      event.transaction.hash,
      event.block.number,
      timestamp,
      JSON.stringify({ subscriptionId })
    );
  }
});

ponder.on("SubscriptionManager:SubscriptionCancelled", async ({ event, context }) => {
  const subscriptionId = event.args.subscriptionId;
  const timestamp = event.args.timestamp;

  const sub = await context.db.find(subscription, { id: subscriptionId });

  await context.db.update(subscription, { id: subscriptionId }).set({
    status: "Cancelled",
    cancelledAt: timestamp,
    updatedAt: timestamp,
  });

  if (sub) {
    await createActivityLog(
      context,
      sub.subscriberId,
      "SUBSCRIPTION_CANCELLED",
      `Subscription cancelled after ${event.args.paymentsCompleted} payments`,
      event.transaction.hash,
      event.block.number,
      timestamp,
      JSON.stringify({
        subscriptionId,
        paymentsCompleted: event.args.paymentsCompleted.toString(),
      })
    );
  }
});

ponder.on("SubscriptionManager:SubscriptionExpired", async ({ event, context }) => {
  const subscriptionId = event.args.subscriptionId;
  const timestamp = event.args.timestamp;

  const sub = await context.db.find(subscription, { id: subscriptionId });

  await context.db.update(subscription, { id: subscriptionId }).set({
    status: "Expired",
    updatedAt: timestamp,
  });

  if (sub) {
    await createActivityLog(
      context,
      sub.subscriberId,
      "SUBSCRIPTION_EXPIRED",
      "Subscription expired - max payments reached",
      event.transaction.hash,
      event.block.number,
      timestamp,
      JSON.stringify({ subscriptionId })
    );
  }
});

ponder.on("SubscriptionManager:SubscriptionAmountUpdated", async ({ event, context }) => {
  const subscriptionId = event.args.subscriptionId;
  const timestamp = BigInt(event.block.timestamp);

  const sub = await context.db.find(subscription, { id: subscriptionId });

  await context.db.update(subscription, { id: subscriptionId }).set({
    amount: event.args.newAmount,
    updatedAt: timestamp,
  });

  if (sub) {
    await createActivityLog(
      context,
      sub.subscriberId,
      "SUBSCRIPTION_AMOUNT_UPDATED",
      `Subscription amount updated: ${event.args.oldAmount} -> ${event.args.newAmount}`,
      event.transaction.hash,
      event.block.number,
      timestamp,
      JSON.stringify({
        subscriptionId,
        oldAmount: event.args.oldAmount.toString(),
        newAmount: event.args.newAmount.toString(),
      })
    );
  }
});
