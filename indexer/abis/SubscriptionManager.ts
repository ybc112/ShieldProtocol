export const SubscriptionManagerAbi = [
  // Events
  {
    type: "event",
    name: "SubscriptionCreated",
    inputs: [
      { name: "subscriptionId", type: "bytes32", indexed: true },
      { name: "subscriber", type: "address", indexed: true },
      { name: "recipient", type: "address", indexed: true },
      { name: "token", type: "address", indexed: false },
      { name: "amount", type: "uint256", indexed: false },
      { name: "billingPeriod", type: "uint8", indexed: false },
    ],
  },
  {
    type: "event",
    name: "PaymentExecuted",
    inputs: [
      { name: "subscriptionId", type: "bytes32", indexed: true },
      { name: "subscriber", type: "address", indexed: true },
      { name: "recipient", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
      { name: "paymentNumber", type: "uint256", indexed: false },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "SubscriptionPaused",
    inputs: [
      { name: "subscriptionId", type: "bytes32", indexed: true },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "SubscriptionResumed",
    inputs: [
      { name: "subscriptionId", type: "bytes32", indexed: true },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "SubscriptionCancelled",
    inputs: [
      { name: "subscriptionId", type: "bytes32", indexed: true },
      { name: "paymentsCompleted", type: "uint256", indexed: false },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "SubscriptionExpired",
    inputs: [
      { name: "subscriptionId", type: "bytes32", indexed: true },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "SubscriptionAmountUpdated",
    inputs: [
      { name: "subscriptionId", type: "bytes32", indexed: true },
      { name: "oldAmount", type: "uint256", indexed: false },
      { name: "newAmount", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "EmergencyWithdrawProposed",
    inputs: [
      { name: "token", type: "address", indexed: true },
      { name: "to", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
      { name: "executeAfter", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "EmergencyWithdrawExecuted",
    inputs: [
      { name: "token", type: "address", indexed: true },
      { name: "to", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "EmergencyWithdrawCancelled",
    inputs: [],
  },
] as const;
