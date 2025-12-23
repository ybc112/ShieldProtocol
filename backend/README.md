# Shield Protocol Backend

自动执行 DCA 策略和订阅付款的后端服务。

## 功能

- **DCA 执行器**: 自动检查并执行到期的 DCA 策略
- **订阅执行器**: 自动处理订阅付款
- **定时调度**: 使用 cron job 定期检查和执行

## 安装

```bash
cd backend
npm install
```

## 配置

1. 复制环境变量模板:
```bash
cp .env.example .env
```

2. 编辑 `.env` 文件:
```env
# RPC URL
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY

# 执行器钱包私钥 (需要 ETH 支付 gas)
EXECUTOR_PRIVATE_KEY=your_private_key

# Cron 调度 (默认每 5 分钟)
CRON_SCHEDULE="*/5 * * * *"

# 是否启用执行 (false = dry-run 模式)
ENABLE_EXECUTION=true
```

## 运行

### 开发模式
```bash
npm run dev
```

### 生产模式
```bash
npm run build
npm start
```

### 单次执行 (测试)
```bash
npm run dev -- --run-once
```

## 架构

```
backend/
├── src/
│   ├── index.ts              # 入口
│   ├── config/
│   │   ├── index.ts          # 配置
│   │   └── contracts.ts      # 合约 ABI 和地址
│   ├── services/
│   │   ├── dcaExecutor.ts    # DCA 执行服务
│   │   └── subscriptionExecutor.ts  # 订阅执行服务
│   └── jobs/
│       └── scheduler.ts      # Cron 调度器
```

## 执行流程

### DCA 执行
```
1. Scheduler 触发 (每 5 分钟)
2. 获取所有活跃策略
3. 检查每个策略是否到期
4. 调用 canExecute() 验证
5. 调用 executeDCA() 执行
6. 等待交易确认
7. 记录结果
```

### 订阅执行
```
1. Scheduler 触发 (每 10 分钟)
2. 遍历已知订阅者
3. 获取每个订阅者的订阅
4. 检查付款是否到期
5. 调用 executePayment() 执行
6. 等待交易确认
7. 记录结果
```

## 注意事项

1. **Gas 费用**: 执行器钱包需要有足够的 ETH 支付 gas
2. **私钥安全**: 不要将私钥提交到代码库
3. **监控**: 建议设置监控和告警
4. **限制**: 当前版本需要手动维护订阅者列表，生产环境建议使用索引器

## 部署建议

### 使用 PM2
```bash
npm run build
pm2 start dist/index.js --name "shield-executor"
```

### 使用 Docker
```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build
CMD ["node", "dist/index.js"]
```
