# Shield Protocol 智能合约架构文档

## 目录

1. [合约架构总览](#1-合约架构总览)
2. [合约详解](#2-合约详解)
3. [核心流程](#3-核心流程)
4. [部署指南](#4-部署指南)
5. [安全考虑](#5-安全考虑)

---

## 1. 合约架构总览

### 1.1 架构图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Shield Protocol 合约架构                           │
└─────────────────────────────────────────────────────────────────────────────┘

                              用户/前端
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         MetaMask Smart Account                               │
│                    (EIP-7702 + ERC-7715 权限)                                │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │
                    ┌───────────┼───────────┐
                    │           │           │
                    ▼           ▼           ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────────────────────────┐
│ Caveat      │ │ Caveat      │ │ Caveat                          │
│ Enforcers   │ │ Enforcers   │ │ Enforcers                       │
│             │ │             │ │                                 │
│ • Spending  │ │ • Allowed   │ │ • Time                          │
│   Limit     │ │   Targets   │ │   Bound                         │
└─────────────┘ └─────────────┘ └─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            ShieldCore.sol                                    │
│                                                                              │
│  核心功能:                                                                   │
│  • 用户 Shield 配置管理                                                      │
│  • 每日/单笔支出限额追踪                                                      │
│  • 白名单合约管理                                                            │
│  • 紧急模式控制                                                              │
│  • 授权执行器管理                                                            │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    │                       │
                    ▼                       ▼
┌─────────────────────────────┐ ┌─────────────────────────────────┐
│     DCAExecutor.sol         │ │   SubscriptionManager.sol       │
│                             │ │                                 │
│  功能:                       │ │  功能:                          │
│  • DCA 策略创建              │ │  • 订阅创建                     │
│  • 自动定投执行              │ │  • 自动支付执行                 │
│  • Uniswap V3 集成          │ │  • 周期管理                     │
│  • 执行历史记录              │ │  • 收款人统计                   │
└─────────────────────────────┘ └─────────────────────────────────┘
                    │                       │
                    └───────────┬───────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Uniswap V3Router                                   │
│                        (外部协议 - 代币兑换)                                  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 合约文件结构

```
contracts/
├── src/
│   ├── interfaces/                    # 接口定义
│   │   ├── IShieldCore.sol           # 核心合约接口
│   │   ├── IDCAExecutor.sol          # DCA 执行器接口
│   │   ├── ISubscriptionManager.sol  # 订阅管理接口
│   │   └── ICaveatEnforcer.sol       # Caveat 执行器接口
│   │
│   ├── core/                          # 核心合约
│   │   └── ShieldCore.sol            # 资产保护核心
│   │
│   ├── strategies/                    # 策略执行器
│   │   └── DCAExecutor.sol           # DCA 定投执行
│   │
│   ├── subscriptions/                 # 订阅模块
│   │   └── SubscriptionManager.sol   # 订阅支付管理
│   │
│   ├── caveats/                       # 权限限制执行器
│   │   ├── SpendingLimitEnforcer.sol # 支出限额
│   │   ├── AllowedTargetsEnforcer.sol# 目标白名单
│   │   └── TimeBoundEnforcer.sol     # 时间限制
│   │
│   └── libraries/                     # 工具库 (预留)
│
├── test/                              # 测试文件
│   └── ShieldCore.t.sol
│
├── script/                            # 部署脚本
│   └── Deploy.s.sol
│
├── foundry.toml                       # Foundry 配置
├── remappings.txt                     # 依赖映射
└── package.json
```

---

## 2. 合约详解

### 2.1 ShieldCore.sol

**职责**: 用户资产保护的核心管理合约

```solidity
// 核心数据结构
struct ShieldConfig {
    uint256 dailySpendLimit;      // 每日支出限额
    uint256 singleTxLimit;        // 单笔交易限额
    uint256 spentToday;           // 今日已支出
    uint256 lastResetTimestamp;   // 上次重置时间
    bool isActive;                // 是否激活
    bool emergencyMode;           // 紧急模式
}
```

**关键函数**:

| 函数 | 可见性 | 说明 |
|------|--------|------|
| `activateShield()` | external | 激活 Shield 防护 |
| `updateShieldConfig()` | external | 更新限额配置 |
| `enableEmergencyMode()` | external | 启用紧急模式 |
| `recordSpending()` | external | 记录支出 (仅授权执行器) |
| `checkSpendingAllowed()` | view | 检查支出是否允许 |
| `addWhitelistedContract()` | external | 添加白名单合约 |

**设计亮点**:
- 每日限额自动重置 (0:00 UTC)
- 支持多代币独立限额
- 紧急模式一键冻结所有操作
- 白名单机制防止恶意合约调用

---

### 2.2 DCAExecutor.sol

**职责**: 执行 DCA (Dollar Cost Averaging) 定投策略

```solidity
// 策略数据结构
struct DCAStrategy {
    address user;                  // 策略所有者
    address sourceToken;           // 源代币 (USDC)
    address targetToken;           // 目标代币 (ETH)
    uint256 amountPerExecution;    // 每次执行金额
    uint256 intervalSeconds;       // 执行间隔
    uint256 totalExecutions;       // 总执行次数
    uint256 executionsCompleted;   // 已完成次数
    StrategyStatus status;         // 策略状态
}
```

**关键函数**:

| 函数 | 可见性 | 说明 |
|------|--------|------|
| `createStrategy()` | external | 创建 DCA 策略 |
| `executeDCA()` | external | 执行单次 DCA |
| `batchExecuteDCA()` | external | 批量执行多个策略 |
| `pauseStrategy()` | external | 暂停策略 |
| `cancelStrategy()` | external | 取消策略 |
| `getAveragePrice()` | view | 获取平均购买价格 |

**执行流程**:
```
1. 验证策略状态 (Active, 未完成, 到达执行时间)
           │
           ▼
2. 调用 ShieldCore.recordSpending() 检查限额
           │
           ▼
3. 从用户账户 transferFrom() 源代币
           │
           ▼
4. 扣除协议手续费
           │
           ▼
5. 调用 Uniswap V3 执行兑换
           │
           ▼
6. 将目标代币发送给用户
           │
           ▼
7. 更新策略状态, 记录执行历史
```

---

### 2.3 SubscriptionManager.sol

**职责**: Web3 原生订阅支付管理

```solidity
// 订阅数据结构
struct Subscription {
    address subscriber;            // 订阅者
    address recipient;             // 收款人
    address token;                 // 支付代币
    uint256 amount;                // 支付金额
    BillingPeriod billingPeriod;   // 周期 (Daily/Weekly/Monthly/Yearly)
    uint256 nextPaymentTime;       // 下次支付时间
    SubscriptionStatus status;     // 状态
}
```

**支持的周期**:
- Daily (每日): 86,400 秒
- Weekly (每周): 604,800 秒
- Monthly (每月): 2,592,000 秒 (30 天)
- Yearly (每年): 31,536,000 秒 (365 天)

**使用场景**:
- 内容创作者订阅
- SaaS 服务订阅
- DAO 会员费
- 定期捐赠

---

### 2.4 Caveat 执行器

#### SpendingLimitEnforcer

**功能**: 限制单次/每日/总计支出金额

```solidity
struct LimitTerms {
    address token;          // 代币地址
    uint256 singleTxLimit;  // 单笔限额
    uint256 dailyLimit;     // 每日限额
    uint256 totalLimit;     // 总计限额
}
```

#### AllowedTargetsEnforcer

**功能**: 限制可调用的目标合约

```solidity
struct TargetTerms {
    bool isWhitelist;       // true = 白名单, false = 黑名单
    address[] targets;      // 目标地址列表
}
```

#### TimeBoundEnforcer

**功能**: 限制权限的有效时间

```solidity
struct TimeTerms {
    uint256 notBefore;      // 开始时间
    uint256 notAfter;       // 结束时间
    uint256 maxExecutions;  // 最大执行次数
}
```

---

## 3. 核心流程

### 3.1 DCA 策略完整流程

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          DCA 策略创建与执行流程                              │
└─────────────────────────────────────────────────────────────────────────────┘

阶段一: 用户设置
──────────────────────────────────────────────────────────────────────────────

   用户                        前端                         MetaMask
    │                           │                              │
    │  1. 配置 DCA 参数          │                              │
    │  (代币对/金额/频率/次数)    │                              │
    │ ─────────────────────────►│                              │
    │                           │                              │
    │                           │  2. 请求 ERC-7715 权限        │
    │                           │ ────────────────────────────►│
    │                           │                              │
    │                           │                   3. 显示权限详情
    │                           │                   (金额/时间/用途)
    │                           │◄──────────────────────────────│
    │                           │                              │
    │  4. 用户在 MetaMask 确认   │                              │
    │ ─────────────────────────────────────────────────────────►│
    │                           │                              │
    │                           │  5. 返回 Delegation          │
    │                           │◄────────────────────────────│


阶段二: 链上创建策略
──────────────────────────────────────────────────────────────────────────────

   前端                      DCAExecutor                    区块链
    │                           │                              │
    │  6. createStrategy()      │                              │
    │ ─────────────────────────►│                              │
    │                           │  7. 验证参数                  │
    │                           │  8. 生成策略 ID               │
    │                           │  9. 存储策略                  │
    │                           │ ────────────────────────────►│
    │                           │                              │
    │                           │  10. emit StrategyCreated    │
    │◄─────────────────────────────────────────────────────────│


阶段三: 自动执行 (由 Keeper 触发)
──────────────────────────────────────────────────────────────────────────────

   Keeper/后端              DCAExecutor                   ShieldCore
       │                        │                              │
       │  11. executeDCA()      │                              │
       │ ──────────────────────►│                              │
       │                        │  12. 验证策略状态             │
       │                        │  13. 验证执行时间             │
       │                        │                              │
       │                        │  14. recordSpending()        │
       │                        │ ────────────────────────────►│
       │                        │                              │
       │                        │                   15. 检查限额
       │                        │                   16. 记录支出
       │                        │◄────────────────────────────│
       │                        │                              │
       │                        │  17. transferFrom() 源代币   │
       │                        │                              │
       │                        │  18. Uniswap 兑换            │
       │                        │                              │
       │                        │  19. 发送目标代币给用户       │
       │                        │                              │
       │                        │  20. 更新策略状态             │
       │                        │  21. emit DCAExecuted        │
       │◄─────────────────────────────────────────────────────│
```

### 3.2 权限验证流程

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            权限验证流程                                      │
└─────────────────────────────────────────────────────────────────────────────┘

    执行请求                 Delegation Framework              Caveat Enforcers
        │                           │                              │
        │  1. 执行请求              │                              │
        │ ─────────────────────────►│                              │
        │                           │                              │
        │                           │  2. 加载 Delegation           │
        │                           │  3. 获取 Caveats 列表         │
        │                           │                              │
        │                           │  4. beforeHook()             │
        │                           │ ────────────────────────────►│
        │                           │                              │
        │                           │       SpendingLimitEnforcer  │
        │                           │       • 检查单笔限额          │
        │                           │       • 检查每日限额          │
        │                           │       • 检查总计限额          │
        │                           │                              │
        │                           │       AllowedTargetsEnforcer │
        │                           │       • 检查目标地址          │
        │                           │                              │
        │                           │       TimeBoundEnforcer      │
        │                           │       • 检查时间范围          │
        │                           │       • 检查执行次数          │
        │                           │                              │
        │                           │  5. 所有 Caveat 通过?        │
        │                           │◄────────────────────────────│
        │                           │                              │
        │                           │  6. 执行目标操作              │
        │                           │                              │
        │                           │  7. afterHook()              │
        │                           │ ────────────────────────────►│
        │                           │       • 更新使用状态          │
        │                           │       • 记录执行              │
        │                           │                              │
        │  8. 返回执行结果          │                              │
        │◄─────────────────────────│                              │
```

---

## 4. 部署指南

### 4.1 环境准备

```bash
# 1. 安装 Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# 2. 克隆项目
git clone https://github.com/shield-protocol/contracts.git
cd contracts

# 3. 安装依赖
forge install OpenZeppelin/openzeppelin-contracts
forge install foundry-rs/forge-std

# 4. 配置环境变量
cp .env.example .env
# 编辑 .env 填入私钥和 RPC URL
```

### 4.2 编译与测试

```bash
# 编译合约
forge build

# 运行测试
forge test

# 运行测试 (详细输出)
forge test -vvv

# 生成 Gas 报告
forge test --gas-report

# 生成覆盖率报告
forge coverage
```

### 4.3 部署到 Sepolia

```bash
# 部署所有合约
forge script script/Deploy.s.sol:DeployShieldProtocol \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast \
  --verify

# 只部署，不广播 (模拟)
forge script script/Deploy.s.sol:DeployShieldProtocol \
  --rpc-url $SEPOLIA_RPC_URL
```

### 4.4 部署后配置

```bash
# 1. 验证合约 (如果自动验证失败)
forge verify-contract <CONTRACT_ADDRESS> src/core/ShieldCore.sol:ShieldCore \
  --chain-id 11155111 \
  --etherscan-api-key $ETHERSCAN_API_KEY

# 2. 添加授权执行器 (如果需要额外的)
cast send <SHIELD_CORE_ADDRESS> "addAuthorizedExecutor(address)" <EXECUTOR_ADDRESS> \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY
```

---

## 5. 安全考虑

### 5.1 已实施的安全措施

| 措施 | 说明 | 合约 |
|------|------|------|
| **ReentrancyGuard** | 防止重入攻击 | ShieldCore, DCAExecutor, SubscriptionManager |
| **Pausable** | 紧急暂停功能 | DCAExecutor, SubscriptionManager |
| **SafeERC20** | 安全的代币操作 | DCAExecutor, SubscriptionManager |
| **访问控制** | 授权执行器机制 | ShieldCore |
| **输入验证** | 参数边界检查 | 所有合约 |
| **限额机制** | 每日/单笔支出限制 | ShieldCore |
| **紧急模式** | 一键冻结功能 | ShieldCore |

### 5.2 潜在风险与缓解

| 风险 | 缓解措施 |
|------|---------|
| **价格操纵** | 使用 TWAP 预言机 (未实现), 设置最小输出金额 |
| **闪电贷攻击** | 限额机制限制单次交易金额 |
| **私钥泄露** | EIP-7702 私钥仍可绑过规则, 需用户保护私钥 |
| **合约升级** | 当前为不可升级, 考虑添加代理模式 |
| **Gas 价格波动** | 策略可暂停, 用户可随时取消 |

### 5.3 审计建议

部署到主网前建议:

1. 进行专业安全审计
2. Bug Bounty 计划
3. 渐进式上线 (限制 TVL)
4. 监控系统部署

---

## 附录

### A. 合约地址 (Sepolia 测试网)

| 合约 | 地址 |
|------|------|
| ShieldCore | `待部署` |
| DCAExecutor | `待部署` |
| SubscriptionManager | `待部署` |
| SpendingLimitEnforcer | `待部署` |
| AllowedTargetsEnforcer | `待部署` |
| TimeBoundEnforcer | `待部署` |

### B. 外部依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| OpenZeppelin Contracts | ^5.0.0 | 基础合约库 |
| Forge Std | ^1.7.0 | 测试框架 |
| Uniswap V3 | - | 代币兑换 |

### C. Gas 估算

| 操作 | 预估 Gas |
|------|----------|
| activateShield | ~80,000 |
| createStrategy | ~150,000 |
| executeDCA | ~250,000 |
| createSubscription | ~120,000 |
| executePayment | ~100,000 |

---

*文档版本: v1.0*
*最后更新: 2024-11-26*
