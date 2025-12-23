import { createConfig } from "ponder";

// Contract ABIs
import { ShieldCoreAbi } from "./abis/ShieldCore";
import { DCAExecutorAbi } from "./abis/DCAExecutor";
import { SubscriptionManagerAbi } from "./abis/SubscriptionManager";
import { RebalanceExecutorAbi } from "./abis/RebalanceExecutor";
import { StopLossExecutorAbi } from "./abis/StopLossExecutor";

export default createConfig({
  chains: {
    sepolia: {
      id: 11155111,
      rpc: process.env.PONDER_RPC_URL_11155111 || "https://rpc.sepolia.org",
    },
  },
  contracts: {
    ShieldCore: {
      chain: "sepolia",
      abi: ShieldCoreAbi,
      address: "0xB581368a7eb6130FFa27BbE29574bF5E231d0c7A",
      startBlock: 7200000,
    },
    DCAExecutor: {
      chain: "sepolia",
      abi: DCAExecutorAbi,
      address: "0x4056Da36F0f980537F8C211fA08FE6530E8D1FaB",
      startBlock: 7200000,
    },
    SubscriptionManager: {
      chain: "sepolia",
      abi: SubscriptionManagerAbi,
      address: "0x6E03B2088E767E5f954fFaa05a7fD6bae14CfE8b",
      startBlock: 7200000,
    },
    RebalanceExecutor: {
      chain: "sepolia",
      abi: RebalanceExecutorAbi,
      address: "0x27a6339DEAC4cd08cE2Ec9a7ff6Bdeeabe1962C2",
      startBlock: 7200000,
    },
    StopLossExecutor: {
      chain: "sepolia",
      abi: StopLossExecutorAbi,
      address: "0x77034c6f5962ECf30C3DC72d33f7409fdCE7c89f",
      startBlock: 7200000,
    },
  },
});
