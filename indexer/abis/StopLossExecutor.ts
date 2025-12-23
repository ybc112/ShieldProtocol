export const StopLossExecutorAbi = [
  // Events
  {
    type: "event",
    name: "StrategyCreated",
    inputs: [
      { name: "strategyId", type: "bytes32", indexed: true },
      { name: "user", type: "address", indexed: true },
      { name: "tokenToSell", type: "address", indexed: false },
      { name: "tokenToReceive", type: "address", indexed: false },
      { name: "amount", type: "uint256", indexed: false },
      { name: "stopLossType", type: "uint8", indexed: false },
      { name: "triggerValue", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "StopLossTriggered",
    inputs: [
      { name: "strategyId", type: "bytes32", indexed: true },
      { name: "user", type: "address", indexed: true },
      { name: "currentPrice", type: "uint256", indexed: false },
      { name: "triggerPrice", type: "uint256", indexed: false },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "StopLossExecuted",
    inputs: [
      { name: "strategyId", type: "bytes32", indexed: true },
      { name: "user", type: "address", indexed: true },
      { name: "amountSold", type: "uint256", indexed: false },
      { name: "amountReceived", type: "uint256", indexed: false },
      { name: "executionPrice", type: "uint256", indexed: false },
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
    name: "StrategyUpdated",
    inputs: [
      { name: "strategyId", type: "bytes32", indexed: true },
      { name: "newTriggerValue", type: "uint256", indexed: false },
      { name: "newMinAmountOut", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "HighestPriceUpdated",
    inputs: [
      { name: "strategyId", type: "bytes32", indexed: true },
      { name: "newHighestPrice", type: "uint256", indexed: false },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
] as const;
