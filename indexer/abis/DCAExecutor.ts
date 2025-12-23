export const DCAExecutorAbi = [
  // Events
  {
    type: "event",
    name: "StrategyCreated",
    inputs: [
      { name: "strategyId", type: "bytes32", indexed: true },
      { name: "user", type: "address", indexed: true },
      { name: "sourceToken", type: "address", indexed: false },
      { name: "targetToken", type: "address", indexed: false },
      { name: "amountPerExecution", type: "uint256", indexed: false },
      { name: "intervalSeconds", type: "uint256", indexed: false },
      { name: "totalExecutions", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "DCAExecuted",
    inputs: [
      { name: "strategyId", type: "bytes32", indexed: true },
      { name: "user", type: "address", indexed: true },
      { name: "amountIn", type: "uint256", indexed: false },
      { name: "amountOut", type: "uint256", indexed: false },
      { name: "executionNumber", type: "uint256", indexed: false },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "StrategyPaused",
    inputs: [
      { name: "strategyId", type: "bytes32", indexed: true },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "StrategyResumed",
    inputs: [
      { name: "strategyId", type: "bytes32", indexed: true },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "StrategyCancelled",
    inputs: [
      { name: "strategyId", type: "bytes32", indexed: true },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "StrategyCompleted",
    inputs: [
      { name: "strategyId", type: "bytes32", indexed: true },
      { name: "totalAmountIn", type: "uint256", indexed: false },
      { name: "totalAmountOut", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "StrategyUpdated",
    inputs: [
      { name: "strategyId", type: "bytes32", indexed: true },
      { name: "newAmountPerExecution", type: "uint256", indexed: false },
      { name: "newMinAmountOut", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "StrategyAutoPaused",
    inputs: [
      { name: "strategyId", type: "bytes32", indexed: true },
      { name: "reason", type: "string", indexed: false },
      { name: "avgPrice", type: "uint256", indexed: false },
      { name: "currentPrice", type: "uint256", indexed: false },
      { name: "deviation", type: "uint256", indexed: false },
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
