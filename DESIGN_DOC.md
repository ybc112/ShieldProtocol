# Shield Protocol 产品设计文档

## 目录

1. [产品概述](#1-产品概述)
2. [用户使用流程](#2-用户使用流程)
3. [页面设计详解](#3-页面设计详解)
4. [设计逻辑与原理](#4-设计逻辑与原理)
5. [技术栈详解](#5-技术栈详解)
6. [项目实现逻辑](#6-项目实现逻辑)
7. [智能合约架构](#7-智能合约架构)
8. [数据流与状态管理](#8-数据流与状态管理)

---

## 1. 产品概述

### 1.1 一句话定义

> Shield Protocol 是一个基于 MetaMask ERC-7715 高级权限的**意图驱动型资产保护与自动化平台**。

### 1.2 解决的核心问题

```
传统 DeFi 痛点                          Shield 解决方案
─────────────────────────────────────────────────────────────
❌ 无限授权风险                    →    ✅ 细粒度权限控制
❌ 每次交易需手动签名              →    ✅ 一次授权，自动执行
❌ 无法设置支出限额                →    ✅ 每日/单笔限额保护
❌ DCA需要每天手动操作             →    ✅ 策略自动执行
❌ 没有原生订阅支付                →    ✅ Web3原生订阅
❌ 出问题后才发现                  →    ✅ 实时监控预警
```

### 1.3 目标用户

| 用户类型 | 需求 | Shield 功能 | 状态 |
|---------|------|------------|------|
| **DeFi 投资者** | 定投、止损、自动复投 | Auto-Pilot 策略 | ✅ 已实现 |
| **安全敏感用户** | 限制授权、防止钓鱼 | Smart Shield 防护 | ✅ 已实现 |
| **内容创作者** | 接收订阅付款 | Web3 Subscriptions | ✅ 已实现 |
| **AI Agent 开发者** | 安全的链上执行权限 | Agent Permission Framework | 🚧 Phase 3 规划中 |

### 1.4 🚀 项目创新点

#### 1.4.1 行业痛点与数据

```
📊 DeFi 安全数据 (2024年)
─────────────────────────────────────────────────────────────
• 因无限授权漏洞损失: $120M+ (Badger DAO, Radiant Capital 等)
• 只有 10.8% 用户定期检查代币授权 (Georgia Tech 研究)
• 平均每个用户有 15+ 个未使用的无限授权
• 手动 DCA 操作: 每月需要 ~150 次点击（每天5次 × 30天）
• 63% 用户因操作复杂而放弃 DeFi
```

#### 1.4.2 核心创新对比

| 创新维度 | 传统方案 | Shield Protocol | 创新价值 |
|---------|---------|-----------------|---------|
| **权限模型** | 无限 token approve | ERC-7715 细粒度权限 | 🔐 最小权限原则 |
| **执行方式** | 用户手动签名每笔交易 | 意图驱动，自动执行 | ⚡ 效率提升 98% |
| **安全边界** | 全权信任 DApp | 密码学强制限额 | 🛡️ 防御深度 |
| **账户类型** | EOA 或需新地址的 AA | EIP-7702 原地升级 | 🔄 无缝迁移 |
| **功能整合** | 多平台、多授权 | 一个平台、一次授权 | 📦 统一体验 |

#### 1.4.3 六大核心创新

**🔐 创新1：首个 ERC-7715 原生权限平台**
```
传统 approve:
用户 → approve(spender, type(uint256).max) → 无限授权 → 终身有效

Shield ERC-7715:
用户 → grantPermission(限额, 时间, 白名单) → 细粒度控制 → 可随时撤销
```
- MetaMask 钱包原生支持，用户界面一致
- 权限边界由密码学保证，非合约信任
- 支持时间限制、金额限制、合约白名单

**⚡ 创新2：意图驱动架构 (Intent-Centric)**
```
用户输入: "我想每天定投 $20 买 ETH"
     ↓
系统解析: 识别为 DCA 策略
     ↓
权限计算: 仅需 $20/天 × 代币 × Uniswap 合约
     ↓
一次授权: MetaMask 弹窗显示精确权限范围
     ↓
自动执行: 后端 Keeper 每日执行，无需再签名
```

**🛡️ 创新3：多层防御安全架构**
```
┌─────────────────────────────────────────────────────┐
│ Layer 5: 紧急冻结 - 一键撤销所有权限                  │
├─────────────────────────────────────────────────────┤
│ Layer 4: 价格保护 - 20%+ 偏差自动暂停策略            │
├─────────────────────────────────────────────────────┤
│ Layer 3: 时间锁 - 配置修改24h + 紧急提币48h 冷却     │
├─────────────────────────────────────────────────────┤
│ Layer 2: 白名单 - 只允许与信任合约交互               │
├─────────────────────────────────────────────────────┤
│ Layer 1: 限额保护 - 每日限额 + 单笔限额 + 代币限额    │
└─────────────────────────────────────────────────────┘
```

**🔄 创新4：EIP-7702 智能账户无缝升级**
| 对比项 | 传统 AA (ERC-4337) | Shield (EIP-7702) |
|--------|-------------------|-------------------|
| 地址变化 | ❌ 需要新地址 | ✅ 保留原 EOA 地址 |
| 历史资产 | 需要迁移 | 自动继承 |
| 社交恢复关联 | 需重新设置 | 保持不变 |
| Gas 优化 | ✅ 批量交易 | ✅ 批量交易 |

**📊 创新5：统一自动化平台**
```
一个平台，一次授权，多种策略：
  ┌─ DCA 定投 ────── 每日/每周自动买入
  │
  ├─ 止损策略 ────── 价格触发自动卖出
  │
  ├─ 再平衡 ──────── 偏离阈值自动调仓
  │
  ├─ 订阅支付 ────── Web3 原生月费订阅
  │
  └─ (规划中) AI 代理 ── 自主 DeFi 操作
```

**📈 创新6：实时数据分析引擎**
- Envio HyperIndex 实时索引链上事件
- GraphQL API 支持复杂查询
- 收益分析、风险评分、Gas 优化建议

#### 1.4.4 竞品对比分析

| 功能 | Shield Protocol | Gelato | Superfluid | revoke.cash | 传统 DApp |
|------|-----------------|--------|------------|-------------|-----------|
| **权限控制** | ERC-7715 原生 | 外部 Keeper | 协议限定 | 事后撤销 | 无限授权 |
| **DCA 自动化** | ✅ 内置 | ✅ | ❌ | ❌ | ❌ |
| **止损/再平衡** | ✅ 内置 | ✅ | ❌ | ❌ | ❌ |
| **订阅支付** | ✅ 内置 | ❌ | ✅ | ❌ | ❌ |
| **支出限额** | ✅ 内置 | ❌ 需手动 | ❌ | ❌ | ❌ |
| **紧急冻结** | ✅ 一键 | 复杂 | 复杂 | 手动逐个 | ❌ |
| **信任模型** | 密码学保证 | 信任 Keeper | 信任协议 | N/A | 全权信任 |
| **Gas 效率** | 智能账户批量 | 按次付费 | 流式 | N/A | 单笔 |
| **数据分析** | ✅ 实时索引 | 基础 | 基础 | ❌ | ❌ |

#### 1.4.5 解决的问题总结

| # | 传统 DeFi 问题 | 影响 | Shield 解决方案 |
|---|---------------|------|----------------|
| 1 | 无限授权风险 | $120M+ 年度损失 | 细粒度时间限制权限 |
| 2 | DCA 操作繁琐 | 每月 150 次操作 | 一次设置自动执行 |
| 3 | 无支出限制 | 私钥泄露全损 | 每日/单笔上限 |
| 4 | 复杂多步 UX | 63% 用户放弃 | 意图驱动简化 |
| 5 | 被动安全（事后撤销）| 发现时已损失 | 主动限额 + 白名单 |
| 6 | 无原生订阅 | Web3 服务难盈利 | 内置订阅模块 |
| 7 | 工具碎片化 | 学习成本高 | 一站式平台 |
| 8 | AA 迁移成本 | 需要新地址 | EIP-7702 原地升级 |

---

## 2. 用户使用流程

### 2.1 整体流程图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Shield Protocol 用户流程                          │
└─────────────────────────────────────────────────────────────────────────┘

    ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
    │  连接钱包  │ ──► │ 激活防护盾 │ ──► │ 创建策略  │ ──► │ 授权权限  │
    └──────────┘     └──────────┘     └──────────┘     └──────────┘
         │                │                │                │
         ▼                ▼                ▼                ▼
    MetaMask Flask   创建Smart Account  选择DCA/订阅等   MetaMask弹窗
    连接 + 切换到     + 设置基础防护      配置具体参数     显示权限详情
    Sepolia测试网    限额
                                                           │
    ┌──────────────────────────────────────────────────────┘
    │
    ▼
┌──────────┐     ┌──────────┐     ┌──────────┐
│ 自动执行  │ ◄── │ 实时监控  │ ◄── │ 数据分析  │
└──────────┘     └──────────┘     └──────────┘
     │                │                │
     ▼                ▼                ▼
 策略按时执行      Envio索引实时      收益分析、风险
 无需手动干预      推送状态更新        评分、Gas优化
```

### 2.2 详细步骤说明

#### 步骤 1：连接钱包

```
用户操作：点击 "Connect Wallet" 按钮
系统响应：
  1. 检测是否安装 MetaMask Flask
  2. 请求连接钱包
  3. 检查网络是否为 Sepolia
  4. 如果不是，提示切换网络

为什么这样设计：
  • ERC-7715 目前只在 MetaMask Flask 中支持
  • EIP-7702 只在支持的测试网可用
  • 需要确保用户环境正确才能使用全部功能
```

#### 步骤 2：激活 Shield 防护

```
用户操作：配置防护参数并点击 "Activate Shield"
系统响应：
  1. 为用户创建 DeleGator Smart Account (EIP-7702)
  2. 将 EOA 升级为智能账户
  3. 保存用户配置的防护规则

为什么这样设计：
  • Smart Account 是 ERC-7715 权限的基础
  • 用户的 EOA 地址不变，但获得智能合约能力
  • 防护规则作为 Caveat 存储，强制执行
```

#### 步骤 3：创建投资策略

```
用户操作：在策略构建器中配置 DCA 参数
系统响应：
  1. 验证参数合理性（金额、频率、时长）
  2. 计算总投资额和预期权限范围
  3. 生成 ERC-7715 权限请求

为什么这样设计：
  • 意图驱动：用户只需说"我想做什么"
  • 系统自动计算需要的最小权限
  • 透明展示总成本，用户知情同意
```

#### 步骤 4：授权权限

```
用户操作：在 MetaMask 弹窗中点击 "Approve"
系统响应：
  1. MetaMask 显示权限详情（金额、时间、用途）
  2. 用户确认后，创建 Delegation
  3. Delegatio0
  .n 存储在链上或本地
  4. 策略激活，开始自动执行

为什么这样设计：
  • 权限完全透明，用户看到具体限制
  • 不是"无限授权"，而是精确的权限边界
  • 用户随时可以撤销
```

#### 步骤 5：自动执行 & 监控

```
系统自动：按策略配置执行交易
用户操作：在 Dashboard 查看执行状态

执行流程：
  1. 到达执行时间
  2. Shield 后端触发执行
  3. 使用 Delegation 代表用户签名
  4. 提交 UserOperation 到 Bundler
  5. Envio 索引交易结果
  6. Dashboard 实时更新

为什么这样设计：
  • 完全自动化，用户无需每天操作
  • 通过 ERC-4337 实现 Gas 抽象
  • Envio 提供实时数据可见性
```

---

## 3. 页面设计详解

### 3.1 页面结构总览

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Shield Protocol                              [Connect Wallet] [0x...] │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐          │
│  │Dashboard│ │Strategies│ │Subscribe│ │ Shield │ │Settings │          │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘          │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                                                                  │   │
│  │                        主内容区域                                 │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Page 1: Dashboard (仪表板)

#### 页面布局

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Dashboard                                                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐           │
│  │ 🛡️ Shield 状态  │ │ 📊 总保护资产    │ │ ⚡ 活跃策略     │           │
│  │                 │ │                 │ │                 │           │
│  │   ✅ 已激活     │ │   $12,450      │ │      3         │           │
│  │                 │ │                 │ │                 │           │
│  └─────────────────┘ └─────────────────┘ └─────────────────┘           │
│                                                                         │
│  ┌─────────────────────────────────────┐ ┌─────────────────────────┐   │
│  │ 📈 资产变化趋势                      │ │ 🔔 最近活动             │   │
│  │                                     │ │                         │   │
│  │     ╭──────────────╮               │ │ • DCA 执行成功          │   │
│  │    ╱                ╲              │ │   20 USDC → 0.0074 ETH  │   │
│  │   ╱                  ──            │ │   2 分钟前              │   │
│  │  ╱                                 │ │                         │   │
│  │ ╱                                  │ │ • 新策略已激活          │   │
│  │╱___________________________        │ │   ETH DCA 30天          │   │
│  │ Nov 20  21  22  23  24  25  26     │ │   1 小时前              │   │
│  │                                     │ │                         │   │
│  └─────────────────────────────────────┘ └─────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ 📋 我的策略                                                      │   │
│  │                                                                  │   │
│  │ ┌────────────────────────────────────────────────────────────┐  │   │
│  │ │ ETH DCA 定投                                    [进行中]   │  │   │
│  │ │ 每日 20 USDC → ETH | 进度: 12/30 天 | 已投入: 240 USDC    │  │   │
│  │ │ ████████████░░░░░░░░░░░░░░░░░░ 40%                        │  │   │
│  │ └────────────────────────────────────────────────────────────┘  │   │
│  │                                                                  │   │
│  │ ┌────────────────────────────────────────────────────────────┐  │   │
│  │ │ 创作者订阅                                       [活跃]    │  │   │
│  │ │ 每月 10 USDC → 0x1234...5678 | 下次扣款: 12月1日          │  │   │
│  │ └────────────────────────────────────────────────────────────┘  │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

#### 设计原因

| 组件 | 设计目的 | 用户价值 |
|------|---------|---------|
| **Shield 状态卡片** | 一眼看到防护是否开启 | 安全感、确认状态 |
| **总保护资产** | 展示 Shield 保护的资产总值 | 了解保护范围 |
| **活跃策略数** | 快速了解运行中的策略数量 | 把控全局 |
| **资产趋势图** | 可视化资产变化 | 直观评估策略效果 |
| **最近活动** | 实时展示执行记录 | 透明、可追溯 |
| **策略列表** | 所有策略的概览 | 管理和监控 |

### 3.3 Page 2: Strategy Builder (策略构建器)

#### 页面布局

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Create New Strategy                                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  选择策略类型                                                     │   │
│  │                                                                  │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │   │
│  │  │   📈     │  │   ⚖️     │  │   🛑     │  │   🔄     │        │   │
│  │  │   DCA    │  │ Rebalance│  │Stop-Loss │  │ Reinvest │        │   │
│  │  │  定投    │  │  再平衡   │  │  止损    │  │  复投    │        │   │
│  │  │ ✓ 选中  │  │          │  │          │  │          │        │   │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘        │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  DCA 策略配置                                                    │   │
│  │                                                                  │   │
│  │  ┌─────────────────────────────────────────────────────────┐   │   │
│  │  │  我想用                                                  │   │   │
│  │  │  ┌─────────┐  ┌──────────────┐                          │   │   │
│  │  │  │   20    │  │  USDC  ▼    │                          │   │   │
│  │  │  └─────────┘  └──────────────┘                          │   │   │
│  │  │                                                          │   │   │
│  │  │  购买                                                    │   │   │
│  │  │  ┌──────────────┐                                       │   │   │
│  │  │  │  ETH  ▼     │                                       │   │   │
│  │  │  └──────────────┘                                       │   │   │
│  │  │                                                          │   │   │
│  │  │  执行频率                                                │   │   │
│  │  │  ○ 每小时  ● 每天  ○ 每周  ○ 每月                       │   │   │
│  │  │                                                          │   │   │
│  │  │  持续时间                                                │   │   │
│  │  │  ┌─────────┐                                            │   │   │
│  │  │  │   30    │  天                                        │   │   │
│  │  │  └─────────┘                                            │   │   │
│  │  │                                                          │   │   │
│  │  │  高级设置 ▼                                              │   │   │
│  │  │  • 最大滑点: 1%                                          │   │   │
│  │  │  • DEX: Uniswap V3                                      │   │   │
│  │  │  • 执行时间: 每天 15:00 UTC                              │   │   │
│  │  └─────────────────────────────────────────────────────────┘   │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  📊 策略摘要                                                     │   │
│  │                                                                  │   │
│  │  • 总投资额: 600 USDC (20 × 30天)                               │   │
│  │  • 预计 Gas 费: ~$2.50 (Pimlico 赞助)                           │   │
│  │  • 权限有效期: 30 天                                             │   │
│  │  • 最大单次授权: 20 USDC                                        │   │
│  │                                                                  │   │
│  │  ⚠️ 重要提示: 您随时可以取消策略并撤销权限                       │   │
│  │                                                                  │   │
│  │               ┌────────────────────────────┐                    │   │
│  │               │    创建策略并授权权限       │                    │   │
│  │               └────────────────────────────┘                    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

#### 设计原因

| 设计元素 | 为什么这样设计 | 达到的效果 |
|---------|---------------|-----------|
| **卡片式策略选择** | 直观展示所有可用策略类型 | 降低认知负担，快速选择 |
| **自然语言式表单** | "我想用 X 购买 Y" | 意图驱动，非技术用户也能理解 |
| **可视化频率选择** | 单选按钮而非下拉框 | 减少点击，一目了然 |
| **策略摘要** | 汇总所有关键信息 | 用户确认前完全知情 |
| **权限透明展示** | 明确显示授权范围 | 建立信任，消除恐惧 |
| **Gas 费提示** | 显示预计成本 | 避免意外，Paymaster 赞助增加吸引力 |

### 3.4 Page 3: Shield Settings (防护设置)

#### 页面布局

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Shield Settings                                                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  🛡️ 防护状态                                    [ 已激活 ✓ ]   │   │
│  │                                                                  │   │
│  │  Smart Account: 0x7a3b...9f2c                                   │   │
│  │  创建时间: 2024-11-20 14:30                                     │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  💰 支出限额                                                     │   │
│  │                                                                  │   │
│  │  每日最大支出                                                    │   │
│  │  ┌─────────────┐                                                │   │
│  │  │    100      │  USDC                                          │   │
│  │  └─────────────┘                                                │   │
│  │  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 已用: 20/100        │   │
│  │                                                                  │   │
│  │  单笔最大交易                                                    │   │
│  │  ┌─────────────┐                                                │   │
│  │  │     50      │  USDC                                          │   │
│  │  └─────────────┘                                                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  ✅ 白名单合约                                                   │   │
│  │                                                                  │   │
│  │  ┌────────────────────────────────────────────────────────────┐ │   │
│  │  │ ✓ Uniswap V3 Router    0x68b3...4a2f     [移除]           │ │   │
│  │  │ ✓ Aave V3 Pool         0x87b3...5c1e     [移除]           │ │   │
│  │  └────────────────────────────────────────────────────────────┘ │   │
│  │                                                                  │   │
│  │  ┌──────────────────────────────┐  ┌────────┐                   │   │
│  │  │ 输入合约地址...              │  │ + 添加 │                   │   │
│  │  └──────────────────────────────┘  └────────┘                   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  🚨 紧急操作                                                     │   │
│  │                                                                  │   │
│  │  ┌─────────────────────────────────────────────────────────┐   │   │
│  │  │  ⚠️ 紧急冻结                                             │   │   │
│  │  │  立即撤销所有活跃的权限授权，停止所有自动执行策略         │   │   │
│  │  │                                                          │   │   │
│  │  │               [ 🔴 紧急冻结所有权限 ]                     │   │   │
│  │  └─────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

#### 设计原因

| 设计元素 | 为什么这样设计 | 达到的效果 |
|---------|---------------|-----------|
| **限额进度条** | 可视化今日支出情况 | 实时感知消费状态 |
| **白名单管理** | 只允许与信任合约交互 | 防止恶意合约调用 |
| **紧急冻结按钮** | 醒目的红色按钮，独立区域 | 紧急情况一键保护 |
| **Smart Account 显示** | 展示底层账户地址 | 透明，高级用户可验证 |

### 3.5 Page 4: Analytics (数据分析 - Envio 驱动)

#### 页面布局

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Analytics                                         Powered by Envio 🔥  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  📈 DCA 策略表现分析                                              │  │
│  │                                                                   │  │
│  │  ETH 累积曲线                     平均购买价格 vs 市场价格        │  │
│  │  ┌─────────────────────┐         ┌─────────────────────┐         │  │
│  │  │         ╭───        │         │  ----  市场价格     │         │  │
│  │  │       ╭─╯           │         │  ───── 您的均价     │         │  │
│  │  │     ╭─╯             │         │     ╱╲   ╱╲        │         │  │
│  │  │   ╭─╯               │         │ ───╱──╲─╱──╲───    │         │  │
│  │  │ ╭─╯                 │         │   ╱    ╳    ╲      │         │  │
│  │  │─╯                   │         │                    │         │  │
│  │  └─────────────────────┘         └─────────────────────┘         │  │
│  │  累积: 0.0892 ETH                 均价: $2,690 | 当前: $2,702    │  │
│  │                                    表现: +0.45% 优于直接购买      │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│  ┌─────────────────────────────┐  ┌─────────────────────────────────┐  │
│  │  🔄 执行历史                 │  │  ⛽ Gas 分析                    │  │
│  │                             │  │                                 │  │
│  │  Nov 26 | 20→0.0074 | ✓    │  │  总节省 Gas: $12.50            │  │
│  │  Nov 25 | 20→0.0076 | ✓    │  │  (vs 手动执行)                  │  │
│  │  Nov 24 | 20→0.0073 | ✓    │  │                                 │  │
│  │  Nov 23 | 20→0.0075 | ✓    │  │  平均 Gas/次: $0.15            │  │
│  │  Nov 22 | 20→0.0071 | ✓    │  │  Paymaster 赞助: 100%          │  │
│  │  ...                        │  │                                 │  │
│  │                             │  │  ┌─────────────────────────┐   │  │
│  │  [查看全部 →]               │  │  │ 最佳执行时间: 04:00 UTC │   │  │
│  │                             │  │  │ (Gas 最低时段)          │   │  │
│  └─────────────────────────────┘  └─────────────────────────────────┘  │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  🔔 安全事件日志                                                  │  │
│  │                                                                   │  │
│  │  时间              事件                          状态             │  │
│  │  ──────────────────────────────────────────────────────────────  │  │
│  │  Nov 26 09:15     DCA 执行 #12                  ✅ 成功          │  │
│  │  Nov 25 09:15     DCA 执行 #11                  ✅ 成功          │  │
│  │  Nov 24 14:30     权限到期提醒                  ⚠️ 提醒          │  │
│  │  Nov 23 09:15     DCA 执行 #10                  ✅ 成功          │  │
│  │                                                                   │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

#### 设计原因

| 设计元素 | 为什么这样设计 | 达到的效果 |
|---------|---------------|-----------|
| **累积曲线图** | 展示 DCA 策略的累积效果 | 直观看到"积少成多" |
| **均价对比图** | 对比用户均价 vs 市场价 | 证明 DCA 策略价值 |
| **执行历史** | 每次执行的详细记录 | 完全透明，可追溯 |
| **Gas 分析** | 展示节省的 Gas 费用 | 突出自动化价值 |
| **最佳执行时间** | 基于历史数据的建议 | 数据驱动优化 |
| **安全日志** | 所有权限相关事件 | 安全审计，建立信任 |

---

## 4. 设计逻辑与原理

### 4.1 为什么采用 "意图驱动" 设计

```
传统 Web3 交互模型:
用户 → 理解技术细节 → 构造交易 → 签名 → 广播

意图驱动模型:
用户 → 表达意图 → 系统处理细节 → 自动执行
```

**设计原理：**

1. **降低认知负担**
   - 用户不需要理解 `approve()`, `transferFrom()` 等概念
   - 只需要知道"我想每天买 20 美元的 ETH"

2. **减少操作步骤**
   - 传统 DCA: 每天登录 → 连接钱包 → 授权 → 交易 → 确认 (5步 × 30天 = 150次操作)
   - Shield DCA: 创建策略 → 一次授权 → 自动执行 (3次操作)

3. **提升安全性**
   - 传统模式容易被钓鱼（假网站诱导签名）
   - 意图模式下，用户只需在真正的 MetaMask 弹窗中确认

### 4.2 为什么选择 ERC-7715 + EIP-7702

```
技术选型对比:

方案 A: 传统 ERC-20 Approve
  ❌ 无限授权风险
  ❌ 无法限制频率/金额
  ❌ 无法自动执行

方案 B: Gelato/Chainlink Keepers
  ⚠️ 需要信任第三方 Keeper 网络
  ⚠️ 需要额外部署合约
  ✅ 可以自动执行

方案 C: ERC-7715 + EIP-7702 (Shield 选择)
  ✅ MetaMask 原生支持
  ✅ 细粒度权限控制
  ✅ 用户完全可控
  ✅ 无需信任第三方
  ✅ 自动执行能力
```

**EIP-7702 的价值：**
- 让 EOA 获得智能合约能力
- 用户地址不变，但功能大幅增强
- 支持批量交易、权限委托等高级功能

**ERC-7715 的价值：**
- 标准化的权限请求格式
- 钱包原生支持，用户界面一致
- 权限边界密码学保证

### 4.3 权限模型设计逻辑

```
传统授权模型:
┌─────────┐    approve(∞)    ┌─────────┐
│  用户   │ ───────────────► │  DApp   │  → 可以转走所有代币!
└─────────┘                  └─────────┘

Shield 权限模型:
┌─────────┐    delegation    ┌─────────┐    ┌──────────┐
│  用户   │ ───────────────► │ Session │ ──►│ Caveats  │
└─────────┘   (有限权限)      │ Account │    │ • 金额限制│
                              └─────────┘    │ • 时间限制│
                                             │ • 频率限制│
                                             │ • 地址限制│
                                             └──────────┘
```

**Caveat (限制条件) 设计：**

| Caveat 类型 | 作用 | 实现方式 |
|-------------|------|---------|
| `SpendingLimitCaveat` | 限制每日/单笔支出 | 检查累计金额 |
| `WhitelistCaveat` | 只允许指定合约 | 检查 target 地址 |
| `TimeBoundCaveat` | 权限有效期 | 检查时间戳 |
| `FrequencyCaveat` | 限制执行频率 | 检查上次执行时间 |

### 4.4 安全设计原则

```
1. 最小权限原则
   用户只授予完成任务所需的最小权限
   例: DCA 只需要 "每天 20 USDC" 权限，而非 "所有 USDC"

2. 可撤销原则
   所有权限随时可撤销
   紧急冻结功能确保用户始终掌控

3. 透明原则
   所有权限在 MetaMask 中清晰显示
   所有执行记录通过 Envio 可查

4. 默认安全原则
   新用户默认有保护限额
   大额交易需要额外确认
```

---

## 5. 技术栈详解

### 5.1 技术栈总览

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            技术栈架构                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  前端层 (Frontend)                                               │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │   │
│  │  │ Next.js  │ │  React   │ │TypeScript│ │ Tailwind │           │   │
│  │  │   14     │ │   18     │ │   5.0    │ │   CSS    │           │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘           │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                    │
│                                    ▼                                    │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  Web3 交互层 (Web3 Interaction)                                  │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────────────────────┐         │   │
│  │  │  Wagmi   │ │   Viem   │ │ MetaMask Delegation      │         │   │
│  │  │   v2     │ │  2.x     │ │ Toolkit                  │         │   │
│  │  └──────────┘ └──────────┘ └──────────────────────────┘         │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                    │
│                                    ▼                                    │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  智能合约层 (Smart Contracts)                                    │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │   │
│  │  │Solidity  │ │ Hardhat  │ │OpenZeppelin│ │Delegation│           │   │
│  │  │ 0.8.24   │ │          │ │ Contracts │ │Framework │           │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘           │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                    │                                    │
│                                    ▼                                    │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  基础设施层 (Infrastructure)                                     │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐           │   │
│  │  │ Pimlico  │ │  Envio   │ │ Sepolia  │ │ MetaMask │           │   │
│  │  │ Bundler  │ │HyperIndex│ │ Testnet  │ │  Flask   │           │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘           │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 5.2 前端技术详解

#### Next.js 14 (App Router)

```typescript
// 为什么选择 Next.js 14:
// 1. App Router 提供更好的数据获取模式
// 2. Server Components 减少客户端 JS 体积
// 3. 内置的路由和布局系统

// app/layout.tsx
export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        <Providers>
          <Header />
          <main>{children}</main>
        </Providers>
      </body>
    </html>
  );
}

// app/dashboard/page.tsx
export default async function DashboardPage() {
  // Server Component: 可以直接获取数据
  const strategies = await fetchUserStrategies();

  return (
    <div>
      <ShieldStatus />
      <StrategyList strategies={strategies} />
      <RecentActivity />
    </div>
  );
}
```

#### Wagmi v2 + Viem

```typescript
// 为什么选择 Wagmi + Viem:
// 1. TypeScript 原生支持，类型安全
// 2. 与 MetaMask Delegation Toolkit 完美集成
// 3. React Hooks 范式，状态管理简单

// hooks/useShield.ts
import { useAccount, useWalletClient } from "wagmi";
import { erc7715ProviderActions } from "@metamask/delegation-toolkit/experimental";

export function useShield() {
  const { address } = useAccount();
  const { data: walletClient } = useWalletClient();

  // 扩展 Wallet Client 支持 ERC-7715
  const extendedClient = walletClient?.extend(erc7715ProviderActions());

  const grantDCAPermission = async (params: DCAParams) => {
    if (!extendedClient) throw new Error("Wallet not connected");

    const permission = await extendedClient.grantPermissions([{
      chainId: sepolia.id,
      expiry: Math.floor(Date.now() / 1000) + params.duration * 86400,
      signer: {
        type: "account",
        data: { address: SHIELD_VAULT_ADDRESS },
      },
      permission: {
        type: "erc20-spend-recurring-limit",
        data: {
          token: params.sourceToken,
          limit: params.amountPerDay.toString(),
          period: 86400,
        },
      },
    }]);

    return permission;
  };

  return {
    grantDCAPermission,
    // ... 其他方法
  };
}
```

#### TailwindCSS + Shadcn/ui

```tsx
// 为什么选择 Tailwind + Shadcn:
// 1. 快速开发，无需写 CSS 文件
// 2. Shadcn 提供高质量可定制组件
// 3. 暗色模式开箱即用

// components/StrategyCard.tsx
import { Card, CardHeader, CardContent } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { Badge } from "@/components/ui/badge";

export function StrategyCard({ strategy }: { strategy: Strategy }) {
  const progress = (strategy.executionsCompleted / strategy.totalExecutions) * 100;

  return (
    <Card className="hover:shadow-lg transition-shadow">
      <CardHeader className="flex flex-row items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="text-lg font-semibold">{strategy.name}</span>
          <Badge variant={strategy.status === "active" ? "default" : "secondary"}>
            {strategy.status}
          </Badge>
        </div>
      </CardHeader>
      <CardContent>
        <div className="space-y-2">
          <div className="text-sm text-muted-foreground">
            每日 {strategy.amountPerDay} {strategy.sourceToken} → {strategy.targetToken}
          </div>
          <Progress value={progress} className="h-2" />
          <div className="text-xs text-muted-foreground">
            进度: {strategy.executionsCompleted}/{strategy.totalExecutions} 天
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
```

### 5.3 Web3 交互层详解

#### MetaMask Delegation Toolkit

```typescript
// 核心概念:
// 1. DeleGator: 用户的 Smart Account
// 2. Delegation: 权限委托
// 3. Caveat: 权限限制条件
// 4. Redemption: 使用委托执行操作

import {
  DelegationFramework,
  createCaveatBuilder,
  SINGLE_DEFAULT_MODE,
} from "@metamask/delegation-toolkit";

// 初始化 Delegation Framework
const framework = new DelegationFramework({
  chainId: sepolia.id,
  delegationManager: DELEGATION_MANAGER_ADDRESS,
  entryPoint: ENTRY_POINT_ADDRESS,
  bundlerUrl: `https://api.pimlico.io/v2/sepolia/rpc?apikey=${PIMLICO_KEY}`,
});

// 创建带有 Caveat 的 Delegation
const createDCADelegation = async (params: DCAParams) => {
  // 构建 Caveat (限制条件)
  const caveats = createCaveatBuilder(sepolia.id)
    // 限制每日支出
    .addCaveat("erc20SpendingLimit", {
      token: params.sourceToken,
      limit: params.amountPerDay,
      period: 86400,
    })
    // 限制有效期
    .addCaveat("timeBound", {
      notBefore: Math.floor(Date.now() / 1000),
      notAfter: Math.floor(Date.now() / 1000) + params.duration * 86400,
    })
    // 只允许调用指定合约
    .addCaveat("allowedTargets", {
      targets: [UNISWAP_ROUTER_ADDRESS],
    })
    .build();

  return caveats;
};
```

### 5.4 智能合约层详解

#### 合约架构

```
contracts/
├── core/
│   ├── ShieldCore.sol          # 核心防护逻辑
│   └── ShieldStorage.sol       # 存储结构
├── strategies/
│   ├── DCAExecutor.sol         # DCA 策略执行器
│   ├── RebalanceExecutor.sol   # 再平衡执行器
│   └── StopLossExecutor.sol    # 止损执行器
├── caveats/
│   ├── SpendingLimitEnforcer.sol
│   ├── WhitelistEnforcer.sol
│   └── FrequencyEnforcer.sol
└── interfaces/
    └── IShieldProtocol.sol
```

#### ShieldCore.sol 实现

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDelegationManager} from "@metamask/delegation-framework/interfaces/IDelegationManager.sol";
import {ICaveatEnforcer} from "@metamask/delegation-framework/interfaces/ICaveatEnforcer.sol";
import {Execution} from "@metamask/delegation-framework/types/Execution.sol";

/**
 * @title ShieldCore
 * @notice 核心防护合约，管理用户的安全配置和策略执行
 *
 * 设计原理:
 * 1. 每个用户有独立的 ShieldConfig 配置
 * 2. 所有策略执行必须通过权限验证
 * 3. 支持紧急冻结功能
 */
contract ShieldCore {
    // ============ 状态变量 ============

    IDelegationManager public immutable delegationManager;

    struct ShieldConfig {
        uint256 dailySpendLimit;      // 每日支出限额
        uint256 singleTxLimit;        // 单笔交易限额
        uint256 spentToday;           // 今日已支出
        uint256 lastResetTimestamp;   // 上次重置时间
        bool isActive;                // 是否激活
        bool emergencyMode;           // 紧急模式
    }

    mapping(address => ShieldConfig) public shields;
    mapping(address => address[]) public whitelistedContracts;

    // ============ 事件 ============

    event ShieldActivated(address indexed user, uint256 dailyLimit, uint256 singleTxLimit);
    event ShieldUpdated(address indexed user, uint256 newDailyLimit, uint256 newSingleTxLimit);
    event EmergencyModeEnabled(address indexed user);
    event EmergencyModeDisabled(address indexed user);
    event SpendingRecorded(address indexed user, uint256 amount, uint256 newTotal);

    // ============ 修饰符 ============

    modifier onlyActiveShield(address user) {
        require(shields[user].isActive, "Shield not active");
        require(!shields[user].emergencyMode, "Emergency mode enabled");
        _;
    }

    // ============ 核心函数 ============

    /**
     * @notice 激活用户的 Shield 防护
     * @param dailyLimit 每日支出限额
     * @param singleTxLimit 单笔交易限额
     *
     * 设计原因:
     * - 用户必须主动激活防护，确保知情同意
     * - 限额在激活时设置，之后可以修改但有冷却期
     */
    function activateShield(
        uint256 dailyLimit,
        uint256 singleTxLimit
    ) external {
        require(!shields[msg.sender].isActive, "Already active");
        require(dailyLimit > 0, "Invalid daily limit");
        require(singleTxLimit <= dailyLimit, "Single tx limit exceeds daily");

        shields[msg.sender] = ShieldConfig({
            dailySpendLimit: dailyLimit,
            singleTxLimit: singleTxLimit,
            spentToday: 0,
            lastResetTimestamp: block.timestamp,
            isActive: true,
            emergencyMode: false
        });

        emit ShieldActivated(msg.sender, dailyLimit, singleTxLimit);
    }

    /**
     * @notice 记录支出并检查限额
     * @param user 用户地址
     * @param amount 支出金额
     *
     * 设计原因:
     * - 在策略执行前调用，确保不超过限额
     * - 每日自动重置计数器
     * - 返回 bool 而非 revert，让调用者决定处理方式
     */
    function recordSpending(
        address user,
        uint256 amount
    ) external onlyActiveShield(user) returns (bool) {
        ShieldConfig storage config = shields[user];

        // 检查是否需要重置每日计数
        if (block.timestamp >= config.lastResetTimestamp + 1 days) {
            config.spentToday = 0;
            config.lastResetTimestamp = block.timestamp;
        }

        // 检查单笔限额
        if (amount > config.singleTxLimit) {
            return false;
        }

        // 检查每日限额
        if (config.spentToday + amount > config.dailySpendLimit) {
            return false;
        }

        // 记录支出
        config.spentToday += amount;

        emit SpendingRecorded(user, amount, config.spentToday);
        return true;
    }

    /**
     * @notice 启用紧急模式
     *
     * 设计原因:
     * - 只能用户本人调用
     * - 立即阻止所有自动执行
     * - 不会自动恢复，需要手动解除
     */
    function enableEmergencyMode() external {
        require(shields[msg.sender].isActive, "Shield not active");
        shields[msg.sender].emergencyMode = true;
        emit EmergencyModeEnabled(msg.sender);
    }

    /**
     * @notice 解除紧急模式
     *
     * 设计原因:
     * - 需要额外确认，防止误操作
     * - 可以添加时间锁定（未来版本）
     */
    function disableEmergencyMode() external {
        require(shields[msg.sender].emergencyMode, "Not in emergency mode");
        shields[msg.sender].emergencyMode = false;
        emit EmergencyModeDisabled(msg.sender);
    }

    // ============ 白名单管理 ============

    function addWhitelistedContract(address contractAddr) external {
        require(shields[msg.sender].isActive, "Shield not active");
        whitelistedContracts[msg.sender].push(contractAddr);
    }

    function isWhitelisted(address user, address contractAddr) public view returns (bool) {
        address[] memory whitelist = whitelistedContracts[user];
        for (uint i = 0; i < whitelist.length; i++) {
            if (whitelist[i] == contractAddr) return true;
        }
        return false;
    }

    // ============ 视图函数 ============

    function getRemainingDailyAllowance(address user) external view returns (uint256) {
        ShieldConfig memory config = shields[user];
        if (!config.isActive) return 0;

        // 如果跨天了，返回完整限额
        if (block.timestamp >= config.lastResetTimestamp + 1 days) {
            return config.dailySpendLimit;
        }

        return config.dailySpendLimit - config.spentToday;
    }
}
```

#### DCAExecutor.sol 实现

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ShieldCore} from "./ShieldCore.sol";

/**
 * @title DCAExecutor
 * @notice 执行 DCA (Dollar Cost Average) 策略
 *
 * 设计原理:
 * 1. 由 Delegation 授权后，可以代表用户执行交易
 * 2. 每次执行前检查 ShieldCore 的限额
 * 3. 使用 Uniswap V3 进行实际的代币兑换
 */
contract DCAExecutor {
    using SafeERC20 for IERC20;

    // ============ 状态变量 ============

    ShieldCore public immutable shieldCore;
    ISwapRouter public immutable swapRouter;

    struct DCAStrategy {
        address user;              // 策略所有者
        address sourceToken;       // 源代币 (如 USDC)
        address targetToken;       // 目标代币 (如 ETH)
        uint256 amountPerExecution;// 每次执行金额
        uint256 intervalSeconds;   // 执行间隔
        uint256 nextExecutionTime; // 下次执行时间
        uint256 executionsRemaining;// 剩余执行次数
        uint24 poolFee;            // Uniswap 池费率
        bool isActive;             // 是否激活
    }

    mapping(bytes32 => DCAStrategy) public strategies;
    mapping(address => bytes32[]) public userStrategies;

    // ============ 事件 ============

    event StrategyCreated(
        bytes32 indexed strategyId,
        address indexed user,
        address sourceToken,
        address targetToken,
        uint256 amountPerExecution,
        uint256 totalExecutions
    );

    event DCAExecuted(
        bytes32 indexed strategyId,
        address indexed user,
        uint256 amountIn,
        uint256 amountOut,
        uint256 executionsRemaining
    );

    event StrategyPaused(bytes32 indexed strategyId);
    event StrategyResumed(bytes32 indexed strategyId);
    event StrategyCancelled(bytes32 indexed strategyId);

    // ============ 构造函数 ============

    constructor(address _shieldCore, address _swapRouter) {
        shieldCore = ShieldCore(_shieldCore);
        swapRouter = ISwapRouter(_swapRouter);
    }

    // ============ 策略管理 ============

    /**
     * @notice 创建 DCA 策略
     *
     * 设计原因:
     * - 策略 ID 使用 hash 生成，确保唯一性
     * - 不在这里请求权限，权限通过 ERC-7715 在前端请求
     * - 只记录策略配置，执行时再验证权限
     */
    function createStrategy(
        address sourceToken,
        address targetToken,
        uint256 amountPerExecution,
        uint256 intervalSeconds,
        uint256 totalExecutions,
        uint24 poolFee
    ) external returns (bytes32 strategyId) {
        require(amountPerExecution > 0, "Amount must be > 0");
        require(totalExecutions > 0, "Must have at least 1 execution");

        // 生成唯一策略 ID
        strategyId = keccak256(abi.encodePacked(
            msg.sender,
            sourceToken,
            targetToken,
            block.timestamp
        ));

        strategies[strategyId] = DCAStrategy({
            user: msg.sender,
            sourceToken: sourceToken,
            targetToken: targetToken,
            amountPerExecution: amountPerExecution,
            intervalSeconds: intervalSeconds,
            nextExecutionTime: block.timestamp, // 立即可执行第一次
            executionsRemaining: totalExecutions,
            poolFee: poolFee,
            isActive: true
        });

        userStrategies[msg.sender].push(strategyId);

        emit StrategyCreated(
            strategyId,
            msg.sender,
            sourceToken,
            targetToken,
            amountPerExecution,
            totalExecutions
        );
    }

    /**
     * @notice 执行 DCA 策略
     * @param strategyId 策略 ID
     *
     * 设计原因:
     * - 任何人都可以调用触发执行（通常是后端服务）
     * - 实际执行需要有效的 Delegation 权限
     * - 检查时间条件和 Shield 限额
     *
     * 执行流程:
     * 1. 验证策略状态和时间条件
     * 2. 通过 ShieldCore 检查限额
     * 3. 使用 Delegation 从用户账户转出代币
     * 4. 调用 Uniswap 执行兑换
     * 5. 更新策略状态
     */
    function executeDCA(bytes32 strategyId) external {
        DCAStrategy storage strategy = strategies[strategyId];

        // 检查策略状态
        require(strategy.isActive, "Strategy not active");
        require(strategy.executionsRemaining > 0, "Strategy completed");
        require(block.timestamp >= strategy.nextExecutionTime, "Too early");

        // 检查 Shield 限额
        bool allowed = shieldCore.recordSpending(
            strategy.user,
            strategy.amountPerExecution
        );
        require(allowed, "Exceeds shield limit");

        // 执行兑换
        // 注意: 实际实现中，这里需要通过 Delegation 权限执行
        // 简化版本直接调用 (需要预先授权给本合约)
        uint256 amountOut = _executeSwap(strategy);

        // 更新策略状态
        strategy.executionsRemaining--;
        strategy.nextExecutionTime = block.timestamp + strategy.intervalSeconds;

        // 如果执行完毕，标记为非活跃
        if (strategy.executionsRemaining == 0) {
            strategy.isActive = false;
        }

        emit DCAExecuted(
            strategyId,
            strategy.user,
            strategy.amountPerExecution,
            amountOut,
            strategy.executionsRemaining
        );
    }

    /**
     * @notice 执行实际的代币兑换
     *
     * 设计原因:
     * - 内部函数，只被 executeDCA 调用
     * - 使用 Uniswap V3 exactInputSingle 进行兑换
     * - 设置合理的滑点保护
     */
    function _executeSwap(
        DCAStrategy storage strategy
    ) internal returns (uint256 amountOut) {
        IERC20 sourceToken = IERC20(strategy.sourceToken);

        // 从用户账户转入代币 (需要 Delegation 权限)
        sourceToken.safeTransferFrom(
            strategy.user,
            address(this),
            strategy.amountPerExecution
        );

        // 授权给 Uniswap Router
        sourceToken.safeApprove(address(swapRouter), strategy.amountPerExecution);

        // 执行兑换
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: strategy.sourceToken,
                tokenOut: strategy.targetToken,
                fee: strategy.poolFee,
                recipient: strategy.user, // 直接发送给用户
                deadline: block.timestamp + 300, // 5分钟超时
                amountIn: strategy.amountPerExecution,
                amountOutMinimum: 0, // 生产环境应该设置最小输出
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);
    }

    // ============ 策略控制 ============

    function pauseStrategy(bytes32 strategyId) external {
        DCAStrategy storage strategy = strategies[strategyId];
        require(strategy.user == msg.sender, "Not owner");
        strategy.isActive = false;
        emit StrategyPaused(strategyId);
    }

    function resumeStrategy(bytes32 strategyId) external {
        DCAStrategy storage strategy = strategies[strategyId];
        require(strategy.user == msg.sender, "Not owner");
        require(strategy.executionsRemaining > 0, "Strategy completed");
        strategy.isActive = true;
        emit StrategyResumed(strategyId);
    }

    function cancelStrategy(bytes32 strategyId) external {
        DCAStrategy storage strategy = strategies[strategyId];
        require(strategy.user == msg.sender, "Not owner");
        strategy.isActive = false;
        strategy.executionsRemaining = 0;
        emit StrategyCancelled(strategyId);
    }
}
```

### 5.5 数据索引层 (Envio)

#### 配置文件

```yaml
# config.yaml
name: shield-protocol-indexer
description: Shield Protocol event indexer
networks:
  - id: 11155111  # Sepolia
    start_block: 5000000
    contracts:
      - name: ShieldCore
        address: "0x..."
        handler: src/handlers/ShieldCore.ts
        events:
          - event: ShieldActivated(address indexed user, uint256 dailyLimit, uint256 singleTxLimit)
          - event: EmergencyModeEnabled(address indexed user)
          - event: SpendingRecorded(address indexed user, uint256 amount, uint256 newTotal)

      - name: DCAExecutor
        address: "0x..."
        handler: src/handlers/DCAExecutor.ts
        events:
          - event: StrategyCreated(bytes32 indexed strategyId, address indexed user, address sourceToken, address targetToken, uint256 amountPerExecution, uint256 totalExecutions)
          - event: DCAExecuted(bytes32 indexed strategyId, address indexed user, uint256 amountIn, uint256 amountOut, uint256 executionsRemaining)
          - event: StrategyCancelled(bytes32 indexed strategyId)
```

#### GraphQL Schema

```graphql
# schema.graphql

type User @entity {
  id: ID!                           # 用户地址
  address: Bytes!
  shield: Shield
  strategies: [Strategy!]! @derivedFrom(field: "user")
  totalInvested: BigInt!            # 总投入金额
  totalExecutions: Int!             # 总执行次数
  createdAt: BigInt!
  updatedAt: BigInt!
}

type Shield @entity {
  id: ID!
  user: User!
  dailyLimit: BigInt!
  singleTxLimit: BigInt!
  spentToday: BigInt!
  isActive: Boolean!
  emergencyMode: Boolean!
  activatedAt: BigInt!
  updatedAt: BigInt!
}

type Strategy @entity {
  id: ID!                           # 策略 ID (bytes32)
  user: User!
  type: StrategyType!
  sourceToken: Token!
  targetToken: Token!
  amountPerExecution: BigInt!
  intervalSeconds: Int!
  totalExecutions: Int!
  executionsCompleted: Int!
  executionsRemaining: Int!
  status: StrategyStatus!
  executions: [Execution!]! @derivedFrom(field: "strategy")
  totalAmountIn: BigInt!
  totalAmountOut: BigInt!
  averagePrice: BigInt!             # 平均购买价格
  createdAt: BigInt!
  updatedAt: BigInt!
}

type Execution @entity {
  id: ID!                           # txHash-logIndex
  strategy: Strategy!
  amountIn: BigInt!
  amountOut: BigInt!
  price: BigInt!                    # 本次执行价格
  gasUsed: BigInt!
  txHash: Bytes!
  blockNumber: BigInt!
  timestamp: BigInt!
}

type Token @entity {
  id: ID!                           # 代币地址
  symbol: String!
  decimals: Int!
  strategies: [Strategy!]!
}

type DailyStats @entity {
  id: ID!                           # date-userId
  user: User!
  date: String!
  totalSpent: BigInt!
  executionCount: Int!
  tokensAcquired: BigInt!
}

enum StrategyType {
  DCA
  REBALANCE
  STOP_LOSS
  YIELD_REINVEST
}

enum StrategyStatus {
  ACTIVE
  PAUSED
  COMPLETED
  CANCELLED
}
```

#### Event Handlers

```typescript
// src/handlers/DCAExecutor.ts
import { DCAExecutor } from "generated";

/**
 * 处理策略创建事件
 *
 * 设计原因:
 * - 创建 Strategy 实体，关联 User
 * - 初始化所有统计字段
 * - 确保 Token 实体存在
 */
DCAExecutor.StrategyCreated.handler(async ({ event, context }) => {
  const strategyId = event.params.strategyId;
  const userId = event.params.user.toLowerCase();

  // 确保用户存在
  let user = await context.User.get(userId);
  if (!user) {
    user = {
      id: userId,
      address: event.params.user,
      totalInvested: 0n,
      totalExecutions: 0,
      createdAt: event.block.timestamp,
      updatedAt: event.block.timestamp,
    };
    await context.User.set(user);
  }

  // 创建策略实体
  const strategy = {
    id: strategyId,
    user_id: userId,
    type: "DCA",
    sourceToken_id: event.params.sourceToken.toLowerCase(),
    targetToken_id: event.params.targetToken.toLowerCase(),
    amountPerExecution: event.params.amountPerExecution,
    intervalSeconds: 86400, // 从合约获取
    totalExecutions: Number(event.params.totalExecutions),
    executionsCompleted: 0,
    executionsRemaining: Number(event.params.totalExecutions),
    status: "ACTIVE",
    totalAmountIn: 0n,
    totalAmountOut: 0n,
    averagePrice: 0n,
    createdAt: event.block.timestamp,
    updatedAt: event.block.timestamp,
  };

  await context.Strategy.set(strategy);
});

/**
 * 处理 DCA 执行事件
 *
 * 设计原因:
 * - 记录每次执行的详细信息
 * - 更新策略的累计统计
 * - 计算平均价格
 * - 更新用户统计
 */
DCAExecutor.DCAExecuted.handler(async ({ event, context }) => {
  const strategyId = event.params.strategyId;
  const executionId = `${event.transaction.hash}-${event.log.logIndex}`;

  // 创建执行记录
  const execution = {
    id: executionId,
    strategy_id: strategyId,
    amountIn: event.params.amountIn,
    amountOut: event.params.amountOut,
    price: (event.params.amountIn * 10n ** 18n) / event.params.amountOut, // 价格计算
    gasUsed: event.transaction.gasUsed || 0n,
    txHash: event.transaction.hash,
    blockNumber: event.block.number,
    timestamp: event.block.timestamp,
  };

  await context.Execution.set(execution);

  // 更新策略统计
  const strategy = await context.Strategy.get(strategyId);
  if (strategy) {
    const newTotalIn = strategy.totalAmountIn + event.params.amountIn;
    const newTotalOut = strategy.totalAmountOut + event.params.amountOut;

    await context.Strategy.set({
      ...strategy,
      executionsCompleted: strategy.executionsCompleted + 1,
      executionsRemaining: Number(event.params.executionsRemaining),
      totalAmountIn: newTotalIn,
      totalAmountOut: newTotalOut,
      averagePrice: newTotalOut > 0n ? (newTotalIn * 10n ** 18n) / newTotalOut : 0n,
      status: Number(event.params.executionsRemaining) === 0 ? "COMPLETED" : "ACTIVE",
      updatedAt: event.block.timestamp,
    });

    // 更新用户统计
    const user = await context.User.get(strategy.user_id);
    if (user) {
      await context.User.set({
        ...user,
        totalInvested: user.totalInvested + event.params.amountIn,
        totalExecutions: user.totalExecutions + 1,
        updatedAt: event.block.timestamp,
      });
    }
  }
});
```

---

## 6. 项目实现逻辑

### 6.1 完整的数据流

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           完整数据流图                                   │
└─────────────────────────────────────────────────────────────────────────┘

用户操作                    前端处理                      链上执行
─────────                   ────────                      ────────

1. 创建策略
   │
   ▼
┌──────────┐           ┌──────────────────┐
│ 填写表单  │ ────────► │ 验证参数         │
└──────────┘           │ 计算权限范围      │
                       │ 构建 Permission   │
                       └────────┬─────────┘
                                │
                                ▼
                       ┌──────────────────┐
                       │ 调用 MetaMask    │
                       │ grantPermissions │
                       └────────┬─────────┘
                                │
                                ▼
                       ┌──────────────────┐          ┌──────────────────┐
                       │ 用户在 MetaMask  │ ────────►│ 链上创建         │
                       │ 确认权限         │          │ Delegation       │
                       └──────────────────┘          └────────┬─────────┘
                                                              │
                                ┌──────────────────────────────┘
                                │
                                ▼
                       ┌──────────────────┐          ┌──────────────────┐
                       │ 调用合约         │ ────────►│ DCAExecutor      │
                       │ createStrategy   │          │ .createStrategy  │
                       └──────────────────┘          └────────┬─────────┘
                                                              │
                                                              ▼
                                                     ┌──────────────────┐
                                                     │ 发出             │
                                                     │ StrategyCreated  │
                                                     │ 事件             │
                                                     └────────┬─────────┘
                                                              │
2. 自动执行 (后端触发)                                         ▼
                                                     ┌──────────────────┐
                       ┌──────────────────┐          │ Envio 索引事件   │
                       │ Backend Cron Job │          │ 更新数据库       │
                       │ 检查到期策略     │          └──────────────────┘
                       └────────┬─────────┘
                                │
                                ▼
                       ┌──────────────────┐          ┌──────────────────┐
                       │ 构建 UserOp      │ ────────►│ Bundler          │
                       │ 使用 Delegation  │          │ 验证 & 打包      │
                       └──────────────────┘          └────────┬─────────┘
                                                              │
                                                              ▼
                                                     ┌──────────────────┐
                                                     │ 链上执行         │
                                                     │ 1. 验证权限      │
                                                     │ 2. 检查限额      │
                                                     │ 3. 执行兑换      │
                                                     └────────┬─────────┘
                                                              │
                                                              ▼
                                                     ┌──────────────────┐
                                                     │ 发出             │
                                                     │ DCAExecuted      │
                                                     │ 事件             │
                                                     └────────┬─────────┘
                                                              │
3. 数据展示                                                    ▼
                                                     ┌──────────────────┐
┌──────────┐           ┌──────────────────┐          │ Envio 索引       │
│ Dashboard│ ◄──────── │ GraphQL 查询     │ ◄────────│ 更新统计         │
│ 更新     │           │ 获取最新数据     │          └──────────────────┘
└──────────┘           └──────────────────┘
```

### 6.2 核心函数调用链

#### 创建 DCA 策略

```typescript
// 1. 前端: 用户填写表单
const dcaParams = {
  sourceToken: USDC_ADDRESS,
  targetToken: WETH_ADDRESS,
  amountPerDay: parseUnits("20", 6),  // 20 USDC
  duration: 30,  // 30 天
};

// 2. 前端: 请求权限
const walletClient = createWalletClient({...}).extend(erc7715ProviderActions());

const permission = await walletClient.grantPermissions([{
  chainId: sepolia.id,
  expiry: Math.floor(Date.now() / 1000) + 30 * 86400,
  signer: {
    type: "account",
    data: { address: DCA_EXECUTOR_ADDRESS },
  },
  permission: {
    type: "erc20-spend-recurring-limit",
    data: {
      token: USDC_ADDRESS,
      limit: parseUnits("20", 6).toString(),
      period: 86400,
    },
  },
}]);

// 3. 前端: 创建链上策略
const hash = await writeContract({
  address: DCA_EXECUTOR_ADDRESS,
  abi: DCAExecutorABI,
  functionName: "createStrategy",
  args: [
    USDC_ADDRESS,
    WETH_ADDRESS,
    parseUnits("20", 6),
    86400,  // 每天执行
    30,     // 30 次
    3000,   // 0.3% 池费率
  ],
});

// 4. 等待确认
await waitForTransaction({ hash });
```

#### 执行 DCA (后端)

```typescript
// backend/services/executor.ts

class DCAExecutorService {
  private framework: DelegationFramework;

  async checkAndExecute() {
    // 1. 从 Envio 获取待执行策略
    const strategies = await this.graphqlClient.query({
      query: GET_DUE_STRATEGIES,
      variables: { currentTime: Math.floor(Date.now() / 1000) },
    });

    for (const strategy of strategies.data.strategies) {
      try {
        await this.executeStrategy(strategy);
      } catch (error) {
        console.error(`Strategy ${strategy.id} failed:`, error);
      }
    }
  }

  async executeStrategy(strategy: Strategy) {
    // 2. 获取用户的 Delegation
    const delegation = await this.getDelegation(strategy.user.address);

    // 3. 构建执行调用数据
    const calldata = encodeFunctionData({
      abi: DCAExecutorABI,
      functionName: "executeDCA",
      args: [strategy.id],
    });

    // 4. 通过 Delegation Framework 构建 UserOperation
    const userOp = await this.framework.createUserOperation({
      delegation,
      executions: [{
        target: DCA_EXECUTOR_ADDRESS,
        value: 0n,
        calldata,
      }],
    });

    // 5. 发送到 Bundler
    const userOpHash = await this.framework.sendUserOperation(userOp);

    // 6. 等待确认
    await this.framework.waitForUserOperation(userOpHash);

    console.log(`Strategy ${strategy.id} executed successfully`);
  }
}
```

### 6.3 状态管理设计

```typescript
// stores/shieldStore.ts
import { create } from "zustand";

interface ShieldState {
  // 用户状态
  isConnected: boolean;
  address: string | null;
  smartAccountAddress: string | null;

  // Shield 状态
  shieldConfig: ShieldConfig | null;
  isShieldActive: boolean;

  // 策略状态
  strategies: Strategy[];
  activeStrategies: Strategy[];

  // 权限状态
  permissions: Permission[];

  // 操作方法
  connect: () => Promise<void>;
  activateShield: (config: ShieldConfig) => Promise<void>;
  createStrategy: (params: StrategyParams) => Promise<void>;
  cancelStrategy: (strategyId: string) => Promise<void>;
  emergencyFreeze: () => Promise<void>;

  // 数据刷新
  refreshStrategies: () => Promise<void>;
  refreshShieldStatus: () => Promise<void>;
}

export const useShieldStore = create<ShieldState>((set, get) => ({
  // 初始状态
  isConnected: false,
  address: null,
  smartAccountAddress: null,
  shieldConfig: null,
  isShieldActive: false,
  strategies: [],
  activeStrategies: [],
  permissions: [],

  // 连接钱包
  connect: async () => {
    const { address } = await connectWallet();
    const smartAccount = await getOrCreateSmartAccount(address);

    set({
      isConnected: true,
      address,
      smartAccountAddress: smartAccount.address,
    });

    // 刷新数据
    await get().refreshShieldStatus();
    await get().refreshStrategies();
  },

  // 激活 Shield
  activateShield: async (config) => {
    const { smartAccountAddress } = get();
    if (!smartAccountAddress) throw new Error("Not connected");

    const hash = await writeContract({
      address: SHIELD_CORE_ADDRESS,
      abi: ShieldCoreABI,
      functionName: "activateShield",
      args: [config.dailyLimit, config.singleTxLimit],
    });

    await waitForTransaction({ hash });

    set({
      shieldConfig: config,
      isShieldActive: true,
    });
  },

  // 创建策略 (包含权限请求)
  createStrategy: async (params) => {
    const { address } = get();
    if (!address) throw new Error("Not connected");

    // 1. 请求权限
    const permission = await requestPermission(params);

    // 2. 创建链上策略
    const hash = await writeContract({
      address: DCA_EXECUTOR_ADDRESS,
      abi: DCAExecutorABI,
      functionName: "createStrategy",
      args: [/* ... */],
    });

    await waitForTransaction({ hash });

    // 3. 刷新列表
    await get().refreshStrategies();
  },

  // 刷新策略数据 (从 Envio)
  refreshStrategies: async () => {
    const { address } = get();
    if (!address) return;

    const result = await graphqlClient.query({
      query: GET_USER_STRATEGIES,
      variables: { userId: address.toLowerCase() },
    });

    const strategies = result.data.strategies;

    set({
      strategies,
      activeStrategies: strategies.filter(s => s.status === "ACTIVE"),
    });
  },

  // ... 其他方法
}));
```

### 6.4 项目目录结构

```
shield-protocol/
├── apps/
│   ├── web/                          # Next.js 前端应用
│   │   ├── src/
│   │   │   ├── app/                  # App Router 页面
│   │   │   │   ├── layout.tsx        # 根布局
│   │   │   │   ├── page.tsx          # 首页
│   │   │   │   ├── dashboard/
│   │   │   │   │   └── page.tsx      # 仪表板
│   │   │   │   ├── strategies/
│   │   │   │   │   ├── page.tsx      # 策略列表
│   │   │   │   │   └── new/
│   │   │   │   │       └── page.tsx  # 创建策略
│   │   │   │   ├── shield/
│   │   │   │   │   └── page.tsx      # Shield 设置
│   │   │   │   └── analytics/
│   │   │   │       └── page.tsx      # 数据分析
│   │   │   │
│   │   │   ├── components/           # React 组件
│   │   │   │   ├── ui/               # 基础 UI 组件 (Shadcn)
│   │   │   │   ├── layout/
│   │   │   │   │   ├── Header.tsx
│   │   │   │   │   ├── Sidebar.tsx
│   │   │   │   │   └── Footer.tsx
│   │   │   │   ├── dashboard/
│   │   │   │   │   ├── ShieldStatusCard.tsx
│   │   │   │   │   ├── StatsCards.tsx
│   │   │   │   │   ├── StrategyList.tsx
│   │   │   │   │   └── RecentActivity.tsx
│   │   │   │   ├── strategies/
│   │   │   │   │   ├── StrategyCard.tsx
│   │   │   │   │   ├── StrategyBuilder.tsx
│   │   │   │   │   ├── DCAForm.tsx
│   │   │   │   │   └── PermissionSummary.tsx
│   │   │   │   ├── shield/
│   │   │   │   │   ├── ShieldConfig.tsx
│   │   │   │   │   ├── SpendingLimitSlider.tsx
│   │   │   │   │   ├── WhitelistManager.tsx
│   │   │   │   │   └── EmergencyButton.tsx
│   │   │   │   └── analytics/
│   │   │   │       ├── PerformanceChart.tsx
│   │   │   │       ├── ExecutionHistory.tsx
│   │   │   │       └── GasAnalysis.tsx
│   │   │   │
│   │   │   ├── hooks/                # Custom Hooks
│   │   │   │   ├── useShield.ts      # Shield 相关操作
│   │   │   │   ├── useStrategy.ts    # 策略相关操作
│   │   │   │   ├── usePermission.ts  # 权限管理
│   │   │   │   └── useAnalytics.ts   # 数据分析
│   │   │   │
│   │   │   ├── stores/               # Zustand 状态管理
│   │   │   │   ├── shieldStore.ts
│   │   │   │   └── uiStore.ts
│   │   │   │
│   │   │   ├── services/             # API 服务
│   │   │   │   ├── graphql/
│   │   │   │   │   ├── client.ts     # GraphQL 客户端
│   │   │   │   │   └── queries.ts    # 查询定义
│   │   │   │   └── contracts/
│   │   │   │       ├── shieldCore.ts
│   │   │   │       └── dcaExecutor.ts
│   │   │   │
│   │   │   ├── lib/                  # 工具函数
│   │   │   │   ├── wagmi.ts          # Wagmi 配置
│   │   │   │   ├── delegation.ts     # Delegation Toolkit 配置
│   │   │   │   └── utils.ts          # 通用工具
│   │   │   │
│   │   │   └── types/                # TypeScript 类型定义
│   │   │       ├── shield.ts
│   │   │       ├── strategy.ts
│   │   │       └── permission.ts
│   │   │
│   │   ├── public/                   # 静态资源
│   │   ├── package.json
│   │   └── next.config.js
│   │
│   └── backend/                      # 后端服务 (可选，用于自动执行)
│       ├── src/
│       │   ├── services/
│       │   │   └── executor.ts       # DCA 执行服务
│       │   ├── jobs/
│       │   │   └── dcaCron.ts        # 定时任务
│       │   └── index.ts
│       └── package.json
│
├── packages/
│   ├── contracts/                    # Solidity 智能合约
│   │   ├── src/
│   │   │   ├── core/
│   │   │   │   ├── ShieldCore.sol
│   │   │   │   └── ShieldStorage.sol
│   │   │   ├── strategies/
│   │   │   │   ├── DCAExecutor.sol
│   │   │   │   ├── RebalanceExecutor.sol
│   │   │   │   └── StopLossExecutor.sol
│   │   │   ├── caveats/
│   │   │   │   ├── SpendingLimitEnforcer.sol
│   │   │   │   └── WhitelistEnforcer.sol
│   │   │   └── interfaces/
│   │   │       └── IShieldProtocol.sol
│   │   ├── test/
│   │   │   ├── ShieldCore.t.sol
│   │   │   └── DCAExecutor.t.sol
│   │   ├── script/
│   │   │   └── Deploy.s.sol
│   │   ├── hardhat.config.ts
│   │   └── package.json
│   │
│   ├── sdk/                          # Shield Protocol SDK
│   │   ├── src/
│   │   │   ├── Shield.ts             # 主类
│   │   │   ├── Strategy.ts           # 策略类
│   │   │   ├── Permission.ts         # 权限类
│   │   │   └── types.ts              # 类型定义
│   │   └── package.json
│   │
│   └── indexer/                      # Envio 索引器
│       ├── src/
│       │   └── handlers/
│       │       ├── ShieldCore.ts
│       │       └── DCAExecutor.ts
│       ├── schema.graphql
│       ├── config.yaml
│       └── package.json
│
├── .env.example                      # 环境变量示例
├── package.json                      # 根 package.json
├── turbo.json                        # Turborepo 配置
└── README.md
```

---

## 9. Phase 3 规划：AI Agent 集成

### 9.1 功能概述

> 🚧 **此功能目前为规划阶段，尚未实现**

AI Agent 集成将允许用户为 AI 代理授予有限的链上执行权限，实现自主 DeFi 操作。

```
┌─────────────────────────────────────────────────────────────────────┐
│                     AI Agent 架构规划                                │
└─────────────────────────────────────────────────────────────────────┘

  用户                    Shield Protocol                    AI Agent
    │                           │                               │
    │  1. 授予有限权限           │                               │
    │ ─────────────────────────►│                               │
    │  (限额、时间、合约白名单)   │                               │
    │                           │                               │
    │                           │  2. 注册 Agent 权限            │
    │                           │◄──────────────────────────────│
    │                           │                               │
    │                           │  3. 在权限边界内执行           │
    │                           │◄──────────────────────────────│
    │                           │                               │
    │  4. 实时监控通知           │                               │
    │◄──────────────────────────│                               │
```

### 9.2 计划功能

| 功能 | 描述 | 状态 |
|------|------|------|
| **🤖 自然语言策略** | "当 ETH RSI < 30 时买入" | 🚧 规划中 |
| **🔒 Agent 权限框架** | 为 AI 代理分配细粒度权限 | 🚧 规划中 |
| **📊 市场分析** | AI 实时分析市场数据 | 🚧 规划中 |
| **⚡ 跨协议优化** | 自动在多个协议间寻找最优收益 | 🚧 规划中 |
| **🛡️ 风险评估** | AI 评估交易风险等级 | 🚧 规划中 |

### 9.3 技术设计

#### Agent 权限接口（规划）

```solidity
// contracts/src/agents/AgentPermissionManager.sol (规划中)

interface IAgentPermissionManager {
    struct AgentPermission {
        address agent;              // AI Agent 地址
        address user;               // 用户地址
        string[] capabilities;      // 允许的操作类型 ["swap", "stake"]
        uint256 maxValuePerTx;      // 单笔最大金额
        uint256 maxDailyVolume;     // 每日最大总额
        address[] allowedProtocols; // 允许交互的协议
        address[] allowedTokens;    // 允许操作的代币
        uint256 expiry;             // 权限过期时间
        bool active;                // 是否激活
    }
    
    /// @notice 授予 AI Agent 权限
    function grantAgentPermission(
        address agent,
        string[] calldata capabilities,
        uint256 maxValuePerTx,
        uint256 maxDailyVolume,
        address[] calldata allowedProtocols,
        address[] calldata allowedTokens,
        uint256 duration
    ) external returns (bytes32 permissionId);
    
    /// @notice AI Agent 执行操作
    function executeAsAgent(
        bytes32 permissionId,
        address target,
        bytes calldata data,
        uint256 value
    ) external;
    
    /// @notice 撤销 Agent 权限
    function revokeAgentPermission(bytes32 permissionId) external;
}
```

#### 前端 SDK（规划）

```typescript
// 计划中的 AI Agent SDK 使用示例

// 1. 授予 AI Agent 权限
const permission = await shield.grantAgentPermission({
  agent: aiAgentAddress,
  capabilities: ["swap", "stake", "provide-liquidity"],
  constraints: {
    maxValuePerTx: parseEther("0.5"),    // 单笔最大 0.5 ETH
    maxDailyVolume: parseEther("5"),     // 每日最大 5 ETH
    allowedProtocols: ["uniswap-v3", "aave-v3", "curve"],
    allowedTokens: ["ETH", "USDC", "WBTC", "DAI"]
  },
  expiry: Date.now() + 30 * 24 * 60 * 60 * 1000 // 30 天有效期
});

// 2. AI Agent 执行操作（在其自己的服务端）
const result = await agentSDK.executeWithPermission({
  permissionId: permission.id,
  action: {
    type: "swap",
    fromToken: "USDC",
    toToken: "ETH",
    amount: parseUnits("100", 6),
    minAmountOut: parseEther("0.04")
  }
});

// 3. 用户可随时查看 Agent 活动
const agentActivity = await shield.getAgentActivity(aiAgentAddress);

// 4. 用户可随时撤销权限
await shield.revokeAgentPermission(permission.id);
```

### 9.4 安全考量

```
AI Agent 权限安全边界：
─────────────────────────────────────────────────────────────
✅ 单笔限额 - 每笔交易不超过设定金额
✅ 每日限额 - 每日操作总额限制
✅ 协议白名单 - 只能与批准的协议交互
✅ 代币白名单 - 只能操作批准的代币
✅ 时间限制 - 权限自动过期
✅ 即时撤销 - 用户可随时撤销所有 Agent 权限
✅ 操作日志 - 所有 Agent 操作透明可查
✅ 异常检测 - 可疑行为自动暂停
```

### 9.5 实现路线图

```
Phase 3: AI Agent Framework (预计 2025 Q3-Q4)
─────────────────────────────────────────────────────────────
├── Q3 2025:
│   ├── [ ] AgentPermissionManager 合约开发
│   ├── [ ] Agent 权限验证机制
│   └── [ ] 基础 Agent SDK
│
├── Q4 2025:
│   ├── [ ] 自然语言策略解析
│   ├── [ ] 市场数据 AI 分析集成
│   ├── [ ] 跨协议收益优化
│   └── [ ] 风险评估模型
│
└── 2026:
    ├── [ ] 第三方 AI Agent 接入
    ├── [ ] Agent 市场（Marketplace）
    └── [ ] Agent 信誉系统
```

---

## 总结

### 设计亮点回顾

| 方面 | 设计决策 | 原因 |
|------|---------|------|
| **交互模式** | 意图驱动 | 降低用户认知负担，提升体验 |
| **权限模型** | ERC-7715 细粒度权限 | 安全、可控、用户信任 |
| **账户类型** | EIP-7702 Smart Account | 保留 EOA 地址，获得 SC 能力 |
| **数据层** | Envio HyperIndex | 高性能索引，实时数据 |
| **执行层** | ERC-4337 UserOperation | Gas 抽象，批量执行 |
| **前端** | Next.js + React | 现代化开发体验，SSR 优化 |

### 核心竞争力

1. **MetaMask 原生** - 直接在钱包层面实现权限控制
2. **用户可控** - 所有权限透明、可撤销
3. **安全优先** - 默认限额保护，紧急冻结机制
4. **数据驱动** - Envio 提供完整的数据分析能力
5. **开发友好** - 完整的 SDK 和文档
6. **AI Ready** - 为 AI Agent 集成预留扩展接口

### 项目阶段

| 阶段 | 内容 | 状态 |
|------|------|------|
| **Phase 1: MVP** | ShieldCore, DCA, 止损, 订阅 | ✅ 已完成 |
| **Phase 2: 增强** | ML 异常检测, 多链, 移动端 | 🚧 进行中 |
| **Phase 3: AI Agent** | Agent 权限框架, 自然语言策略 | 📋 规划中 |
| **Phase 4: 生态** | SDK, 策略市场, DAO 治理 | 📋 规划中 |

---

*文档版本: v1.1*
*最后更新: 2024-12-21*
