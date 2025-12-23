export const ShieldCoreAbi = [
  // Events
  {
    type: "event",
    name: "ShieldActivated",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "dailyLimit", type: "uint256", indexed: false },
      { name: "singleTxLimit", type: "uint256", indexed: false },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "ShieldConfigUpdated",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "newDailyLimit", type: "uint256", indexed: false },
      { name: "newSingleTxLimit", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "ShieldDeactivated",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "EmergencyModeEnabled",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "EmergencyModeDisabled",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "SpendingRecorded",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "token", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
      { name: "dailyTotal", type: "uint256", indexed: false },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "ContractWhitelisted",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "contractAddress", type: "address", indexed: true },
    ],
  },
  {
    type: "event",
    name: "ContractRemovedFromWhitelist",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "contractAddress", type: "address", indexed: true },
    ],
  },
  {
    type: "event",
    name: "DailyLimitReset",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "timestamp", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "ConfigUpdateProposed",
    inputs: [
      { name: "user", type: "address", indexed: true },
      { name: "newDailyLimit", type: "uint256", indexed: false },
      { name: "newSingleTxLimit", type: "uint256", indexed: false },
      { name: "effectiveTime", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "ConfigUpdateExecuted",
    inputs: [
      { name: "user", type: "address", indexed: true },
    ],
  },
  {
    type: "event",
    name: "ConfigUpdateCancelled",
    inputs: [
      { name: "user", type: "address", indexed: true },
    ],
  },
  {
    type: "event",
    name: "WhitelistModeEnabled",
    inputs: [
      { name: "user", type: "address", indexed: true },
    ],
  },
  {
    type: "event",
    name: "WhitelistModeDisabled",
    inputs: [
      { name: "user", type: "address", indexed: true },
    ],
  },
  {
    type: "event",
    name: "AuthorizedExecutorAdded",
    inputs: [
      { name: "executor", type: "address", indexed: true },
    ],
  },
  {
    type: "event",
    name: "AuthorizedExecutorRemoved",
    inputs: [
      { name: "executor", type: "address", indexed: true },
    ],
  },
  {
    type: "event",
    name: "ProtocolPausedChanged",
    inputs: [
      { name: "paused", type: "bool", indexed: false },
    ],
  },
] as const;
