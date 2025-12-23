export const RebalanceExecutorAbi = [
  // Events
  {
    type: "event",
    name: "StrategyCreated",
    inputs: [
      { name: "strategyId", type: "bytes32", indexed: true },
      { name: "user", type: "address", indexed: true },
      { name: "tokens", type: "address[]", indexed: false },
      { name: "targetWeights", type: "uint256[]", indexed: false },
      { name: "rebalanceThreshold", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "RebalanceExecuted",
    inputs: [
      { name: "strategyId", type: "bytes32", indexed: true },
      { name: "user", type: "address", indexed: true },
      { name: "totalValue", type: "uint256", indexed: false },
      { name: "rebalanceNumber", type: "uint256", indexed: false },
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
    name: "AllocationUpdated",
    inputs: [
      { name: "strategyId", type: "bytes32", indexed: true },
      { name: "token", type: "address", indexed: true },
      { name: "oldWeight", type: "uint256", indexed: false },
      { name: "newWeight", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "ThresholdUpdated",
    inputs: [
      { name: "strategyId", type: "bytes32", indexed: true },
      { name: "oldThreshold", type: "uint256", indexed: false },
      { name: "newThreshold", type: "uint256", indexed: false },
    ],
  },
] as const;
