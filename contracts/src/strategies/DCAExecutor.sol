// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDCAExecutor} from "../interfaces/IDCAExecutor.sol";
import {IShieldCore} from "../interfaces/IShieldCore.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

// Uniswap V3 接口
interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}

/**
 * @title DCAExecutor
 * @author Shield Protocol Team
 * @notice DCA (Dollar Cost Averaging) 策略执行合约
 * @dev 实现了自动化定投策略的创建、执行和管理
 *
 * 核心功能:
 * 1. 创建 DCA 策略 (指定代币对、金额、频率、次数)
 * 2. 自动执行定投 (通过 Keeper 或任何人触发)
 * 3. 与 ShieldCore 集成进行限额检查
 * 4. 使用 Uniswap V3 执行实际兑换
 *
 * 执行流程:
 * 1. 用户创建策略并授予 ERC-7715 权限
 * 2. 到达执行时间后，Keeper 调用 executeDCA
 * 3. 合约验证权限、检查限额
 * 4. 从用户账户转入代币
 * 5. 通过 Uniswap 执行兑换
 * 6. 将目标代币发送给用户
 */
contract DCAExecutor is IDCAExecutor, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============ 常量 ============

    /// @notice 最小执行间隔 (1 小时)
    uint256 public constant MIN_INTERVAL = 3600;

    /// @notice 最大执行间隔 (365 天)
    uint256 public constant MAX_INTERVAL = 365 days;

    /// @notice 最大单个策略执行次数
    uint256 public constant MAX_EXECUTIONS = 1000;

    /// @notice 交易超时时间
    uint256 public constant SWAP_DEADLINE = 300; // 5 分钟

    /// @notice 紧急提币延迟时间 (48 小时)
    uint256 public constant EMERGENCY_WITHDRAW_DELAY = 48 hours;

    /// @notice 价格偏差容忍度 (20%)
    uint256 public constant MAX_PRICE_DEVIATION = 20;

    // ============ 不可变量 ============

    /// @notice Shield 核心合约
    IShieldCore public immutable shieldCore;

    /// @notice Uniswap V3 路由合约
    ISwapRouter public immutable swapRouter;

    /// @notice WETH 合约地址
    address public immutable WETH;

    // ============ 状态变量 ============

    /// @notice 策略 ID => 策略详情
    mapping(bytes32 => DCAStrategy) private _strategies;

    /// @notice 用户地址 => 策略 ID 数组
    mapping(address => bytes32[]) private _userStrategies;

    /// @notice 策略 ID => 执行记录数组
    mapping(bytes32 => ExecutionRecord[]) private _executionHistory;

    /// @notice 策略 ID => 总输入金额
    mapping(bytes32 => uint256) private _totalAmountIn;

    /// @notice 策略 ID => 总输出金额
    mapping(bytes32 => uint256) private _totalAmountOut;

    /// @notice 所有策略 ID 列表 (用于 getPendingStrategies)
    bytes32[] private _allStrategyIds;

    /// @notice 策略 ID => 在 _allStrategyIds 中的索引
    mapping(bytes32 => uint256) private _strategyIndex;

    /// @notice 协议手续费 (基点, 100 = 1%)
    uint256 public protocolFeeBps;

    /// @notice 手续费接收地址
    address public feeRecipient;

    /// @notice 策略 ID => 上次执行价格 (18 位精度)
    mapping(bytes32 => uint256) public lastExecutionPrice;

    /// @notice 策略 ID => 滚动平均价格 (18 位精度)
    mapping(bytes32 => uint256) public rollingAvgPrice;

    /// @notice 待执行的紧急提币
    struct PendingEmergencyWithdraw {
        address token;
        address to;
        uint256 amount;
        uint256 executeAfter;
        bool pending;
    }

    /// @notice 待执行的紧急提币请求
    PendingEmergencyWithdraw public pendingWithdraw;

    // ============ 修饰符 ============

    /// @notice 确保是策略所有者
    modifier onlyStrategyOwner(bytes32 strategyId) {
        if (_strategies[strategyId].user != msg.sender) {
            revert NotStrategyOwner();
        }
        _;
    }

    /// @notice 确保策略存在
    modifier strategyExists(bytes32 strategyId) {
        if (_strategies[strategyId].user == address(0)) {
            revert StrategyNotFound();
        }
        _;
    }

    // ============ 构造函数 ============

    /**
     * @notice 构造函数
     * @param _shieldCore ShieldCore 合约地址
     * @param _swapRouter Uniswap V3 路由合约地址
     * @param _weth WETH 合约地址
     */
    constructor(
        address _shieldCore,
        address _swapRouter,
        address _weth
    ) Ownable(msg.sender) {
        require(_shieldCore != address(0), "Invalid ShieldCore");
        require(_swapRouter != address(0), "Invalid SwapRouter");
        require(_weth != address(0), "Invalid WETH");

        shieldCore = IShieldCore(_shieldCore);
        swapRouter = ISwapRouter(_swapRouter);
        WETH = _weth;

        feeRecipient = msg.sender;
        protocolFeeBps = 30; // 0.3% 默认手续费
    }

    // ============ 管理函数 ============

    /// @notice 设置协议手续费
    function setProtocolFee(uint256 feeBps) external onlyOwner {
        require(feeBps <= 100, "Fee too high"); // 最高 1%
        protocolFeeBps = feeBps;
    }

    /// @notice 设置手续费接收地址
    function setFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        feeRecipient = recipient;
    }

    /// @notice 暂停合约
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice 恢复合约
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ 策略管理函数 ============

    /**
     * @notice 创建 DCA 策略
     * @param params 策略参数
     * @return strategyId 策略 ID
     *
     * 注意:
     * - 创建策略不需要立即授权代币
     * - 用户需要通过 ERC-7715 授权权限
     * - 第一次执行时间设为立即可执行
     */
    function createStrategy(
        CreateStrategyParams calldata params
    ) external whenNotPaused nonReentrant returns (bytes32 strategyId) {
        // 参数验证
        if (params.sourceToken == address(0)) revert InvalidParameters();
        if (params.targetToken == address(0)) revert InvalidParameters();
        if (params.sourceToken == params.targetToken) revert InvalidParameters();
        if (params.amountPerExecution == 0) revert InvalidParameters();
        if (params.intervalSeconds < MIN_INTERVAL) revert InvalidParameters();
        if (params.intervalSeconds > MAX_INTERVAL) revert InvalidParameters();
        if (params.totalExecutions == 0) revert InvalidParameters();
        if (params.totalExecutions > MAX_EXECUTIONS) revert InvalidParameters();

        // 生成唯一策略 ID
        strategyId = keccak256(abi.encodePacked(
            msg.sender,
            params.sourceToken,
            params.targetToken,
            params.amountPerExecution,
            block.timestamp,
            block.number
        ));

        // 确保 ID 唯一
        require(_strategies[strategyId].user == address(0), "Strategy ID collision");

        // 创建策略
        _strategies[strategyId] = DCAStrategy({
            user: msg.sender,
            sourceToken: params.sourceToken,
            targetToken: params.targetToken,
            amountPerExecution: params.amountPerExecution,
            minAmountOut: params.minAmountOut,
            intervalSeconds: params.intervalSeconds,
            nextExecutionTime: block.timestamp, // 立即可执行第一次
            totalExecutions: params.totalExecutions,
            executionsCompleted: 0,
            poolFee: params.poolFee,
            status: StrategyStatus.Active,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        // 记录用户策略
        _userStrategies[msg.sender].push(strategyId);

        // 记录到全局策略列表
        _strategyIndex[strategyId] = _allStrategyIds.length;
        _allStrategyIds.push(strategyId);

        emit StrategyCreated(
            strategyId,
            msg.sender,
            params.sourceToken,
            params.targetToken,
            params.amountPerExecution,
            params.intervalSeconds,
            params.totalExecutions
        );
    }

    /**
     * @notice 执行 DCA 策略
     * @param strategyId 策略 ID
     * @return amountOut 输出金额
     *
     * 执行流程:
     * 1. 验证策略状态和时间条件
     * 2. 通过 ShieldCore 记录支出 (检查限额)
     * 3. 从用户账户转入代币
     * 4. 执行 Uniswap 兑换
     * 5. 将目标代币发送给用户
     * 6. 更新策略状态
     */
    function executeDCA(
        bytes32 strategyId
    ) external strategyExists(strategyId) whenNotPaused nonReentrant returns (uint256 amountOut) {
        return _executeDCAInternal(strategyId);
    }

    /**
     * @notice 批量执行多个策略
     * @param strategyIds 策略 ID 数组
     * @return results 每个策略的执行结果
     */
    function batchExecuteDCA(
        bytes32[] calldata strategyIds
    ) external whenNotPaused nonReentrant returns (uint256[] memory results) {
        results = new uint256[](strategyIds.length);

        for (uint256 i = 0; i < strategyIds.length; i++) {
            // 直接调用内部函数，避免重入锁冲突
            try this.executeDCAInternal(strategyIds[i]) returns (uint256 amountOut) {
                results[i] = amountOut;
            } catch {
                results[i] = 0;
            }
        }
    }

    /// @notice 内部执行函数 (用于批量执行的 try-catch)
    function executeDCAInternal(bytes32 strategyId) external returns (uint256) {
        require(msg.sender == address(this), "Only internal");
        // 检查策略存在
        if (_strategies[strategyId].user == address(0)) {
            revert StrategyNotFound();
        }
        return _executeDCAInternal(strategyId);
    }

    /**
     * @notice 内部支付执行逻辑 (无重入锁)
     */
    function _executeDCAInternal(bytes32 strategyId) internal returns (uint256 amountOut) {
        DCAStrategy storage strategy = _strategies[strategyId];

        // 检查策略状态
        if (strategy.status != StrategyStatus.Active) {
            revert StrategyNotActive();
        }

        // 检查执行次数
        if (strategy.executionsCompleted >= strategy.totalExecutions) {
            revert StrategyAlreadyCompleted();
        }

        // 检查执行时间
        if (block.timestamp < strategy.nextExecutionTime) {
            revert ExecutionTooEarly(strategy.nextExecutionTime);
        }

        // 通过 ShieldCore 检查和记录支出
        // 注意: recordSpending 会在限额超出时直接 revert
        shieldCore.recordSpending(
            strategy.user,
            strategy.sourceToken,
            strategy.amountPerExecution
        );

        // 从用户账户转入代币
        IERC20(strategy.sourceToken).safeTransferFrom(
            strategy.user,
            address(this),
            strategy.amountPerExecution
        );

        // 计算实际交换金额 (扣除手续费)
        uint256 feeAmount = (strategy.amountPerExecution * protocolFeeBps) / 10000;
        uint256 swapAmount = strategy.amountPerExecution - feeAmount;

        // 转移手续费
        if (feeAmount > 0 && feeRecipient != address(0)) {
            IERC20(strategy.sourceToken).safeTransfer(feeRecipient, feeAmount);
        }

        // 执行 Uniswap 兑换
        amountOut = _executeSwap(
            strategy.sourceToken,
            strategy.targetToken,
            swapAmount,
            strategy.minAmountOut,
            strategy.poolFee,
            strategy.user
        );

        // 检查滑点
        if (amountOut < strategy.minAmountOut) {
            revert SlippageExceeded(strategy.minAmountOut, amountOut);
        }

        // 价格异常检测
        _checkAndUpdatePrice(strategyId, strategy.amountPerExecution, amountOut);

        // 更新策略状态
        strategy.executionsCompleted++;
        strategy.nextExecutionTime = block.timestamp + strategy.intervalSeconds;
        strategy.updatedAt = block.timestamp;

        // 记录执行历史
        _executionHistory[strategyId].push(ExecutionRecord({
            strategyId: strategyId,
            amountIn: strategy.amountPerExecution,
            amountOut: amountOut,
            executionPrice: (strategy.amountPerExecution * 1e18) / amountOut,
            gasUsed: 0, // 由外部记录
            timestamp: block.timestamp
        }));

        // 更新累计金额
        _totalAmountIn[strategyId] += strategy.amountPerExecution;
        _totalAmountOut[strategyId] += amountOut;

        // 检查是否完成
        if (strategy.executionsCompleted >= strategy.totalExecutions) {
            strategy.status = StrategyStatus.Completed;
            emit StrategyCompleted(
                strategyId,
                _totalAmountIn[strategyId],
                _totalAmountOut[strategyId]
            );
        }

        emit DCAExecuted(
            strategyId,
            strategy.user,
            strategy.amountPerExecution,
            amountOut,
            strategy.executionsCompleted,
            block.timestamp
        );
    }

    /**
     * @notice 暂停策略
     * @param strategyId 策略 ID
     */
    function pauseStrategy(
        bytes32 strategyId
    ) external strategyExists(strategyId) onlyStrategyOwner(strategyId) {
        DCAStrategy storage strategy = _strategies[strategyId];

        if (strategy.status != StrategyStatus.Active) {
            revert StrategyNotActive();
        }

        strategy.status = StrategyStatus.Paused;
        strategy.updatedAt = block.timestamp;

        emit StrategyPaused(strategyId, block.timestamp);
    }

    /**
     * @notice 恢复策略
     * @param strategyId 策略 ID
     */
    function resumeStrategy(
        bytes32 strategyId
    ) external strategyExists(strategyId) onlyStrategyOwner(strategyId) {
        DCAStrategy storage strategy = _strategies[strategyId];

        require(strategy.status == StrategyStatus.Paused, "Not paused");
        require(strategy.executionsCompleted < strategy.totalExecutions, "Already completed");

        strategy.status = StrategyStatus.Active;
        strategy.updatedAt = block.timestamp;

        emit StrategyResumed(strategyId, block.timestamp);
    }

    /**
     * @notice 取消策略
     * @param strategyId 策略 ID
     */
    function cancelStrategy(
        bytes32 strategyId
    ) external strategyExists(strategyId) onlyStrategyOwner(strategyId) {
        DCAStrategy storage strategy = _strategies[strategyId];

        if (strategy.status == StrategyStatus.Cancelled) {
            revert("Already cancelled");
        }

        strategy.status = StrategyStatus.Cancelled;
        strategy.updatedAt = block.timestamp;

        emit StrategyCancelled(strategyId, block.timestamp);
    }

    /**
     * @notice 更新策略参数
     * @param strategyId 策略 ID
     * @param newAmountPerExecution 新的每次执行金额
     * @param newMinAmountOut 新的最小输出金额
     */
    function updateStrategy(
        bytes32 strategyId,
        uint256 newAmountPerExecution,
        uint256 newMinAmountOut
    ) external strategyExists(strategyId) onlyStrategyOwner(strategyId) {
        if (newAmountPerExecution == 0) revert InvalidParameters();

        DCAStrategy storage strategy = _strategies[strategyId];
        strategy.amountPerExecution = newAmountPerExecution;
        strategy.minAmountOut = newMinAmountOut;
        strategy.updatedAt = block.timestamp;

        emit StrategyUpdated(strategyId, newAmountPerExecution, newMinAmountOut);
    }

    // ============ 视图函数 ============

    /**
     * @notice 获取策略详情
     */
    function getStrategy(bytes32 strategyId) external view strategyExists(strategyId) returns (DCAStrategy memory) {
        return _strategies[strategyId];
    }

    /**
     * @notice 获取用户的所有策略 ID
     */
    function getUserStrategies(address user) external view returns (bytes32[] memory) {
        return _userStrategies[user];
    }

    /**
     * @notice 获取待执行的策略 (支持分页)
     * @param startIndex 起始索引
     * @param limit 返回数量限制
     * @return strategyIds 待执行的策略 ID 数组
     * @return nextIndex 下一个起始索引 (0 表示结束)
     *
     * 安全改进: 添加分页支持，避免 gas 耗尽
     */
    function getPendingStrategies(
        uint256 startIndex,
        uint256 limit
    ) external view returns (bytes32[] memory strategyIds, uint256 nextIndex) {
        uint256 count = 0;
        uint256 maxLen = limit;
        bytes32[] memory temp = new bytes32[](maxLen);

        uint256 i = startIndex;
        while (i < _allStrategyIds.length && count < maxLen) {
            bytes32 sid = _allStrategyIds[i];
            DCAStrategy memory strategy = _strategies[sid];

            // 检查策略是否可执行
            if (
                strategy.status == StrategyStatus.Active &&
                strategy.executionsCompleted < strategy.totalExecutions &&
                block.timestamp >= strategy.nextExecutionTime
            ) {
                temp[count] = sid;
                count++;
            }
            i++;
        }

        // 返回下一个索引 (0 表示已到末尾)
        nextIndex = i < _allStrategyIds.length ? i : 0;

        // 创建精确大小的返回数组
        strategyIds = new bytes32[](count);
        for (uint256 j = 0; j < count; j++) {
            strategyIds[j] = temp[j];
        }
    }

    /**
     * @notice 检查策略是否可执行
     */
    function canExecute(bytes32 strategyId) external view returns (bool, string memory) {
        DCAStrategy memory strategy = _strategies[strategyId];

        if (strategy.user == address(0)) {
            return (false, "Strategy not found");
        }

        if (strategy.status != StrategyStatus.Active) {
            return (false, "Strategy not active");
        }

        if (strategy.executionsCompleted >= strategy.totalExecutions) {
            return (false, "Strategy completed");
        }

        if (block.timestamp < strategy.nextExecutionTime) {
            return (false, "Execution too early");
        }

        // 检查 Shield 限额
        (bool allowed, string memory reason) = shieldCore.checkSpendingAllowed(
            strategy.user,
            strategy.sourceToken,
            strategy.amountPerExecution
        );

        if (!allowed) {
            return (false, reason);
        }

        // 检查余额
        uint256 balance = IERC20(strategy.sourceToken).balanceOf(strategy.user);
        if (balance < strategy.amountPerExecution) {
            return (false, "Insufficient balance");
        }

        // 检查授权
        uint256 allowance = IERC20(strategy.sourceToken).allowance(strategy.user, address(this));
        if (allowance < strategy.amountPerExecution) {
            return (false, "Insufficient allowance");
        }

        return (true, "");
    }

    /**
     * @notice 获取策略的执行历史
     */
    function getExecutionHistory(
        bytes32 strategyId
    ) external view returns (ExecutionRecord[] memory) {
        return _executionHistory[strategyId];
    }

    /**
     * @notice 计算策略的平均购买价格
     */
    function getAveragePrice(bytes32 strategyId) external view returns (uint256) {
        uint256 totalIn = _totalAmountIn[strategyId];
        uint256 totalOut = _totalAmountOut[strategyId];

        if (totalOut == 0) return 0;

        return (totalIn * 1e18) / totalOut;
    }

    /**
     * @notice 获取策略的累计统计
     */
    function getStrategyStats(bytes32 strategyId) external view returns (
        uint256 totalIn,
        uint256 totalOut,
        uint256 averagePrice,
        uint256 executionsCompleted
    ) {
        DCAStrategy memory strategy = _strategies[strategyId];
        totalIn = _totalAmountIn[strategyId];
        totalOut = _totalAmountOut[strategyId];
        averagePrice = totalOut > 0 ? (totalIn * 1e18) / totalOut : 0;
        executionsCompleted = strategy.executionsCompleted;
    }

    // ============ 内部函数 ============

    /**
     * @notice 执行 Uniswap 兑换
     * @param tokenIn 输入代币
     * @param tokenOut 输出代币
     * @param amountIn 输入金额
     * @param minAmountOut 最小输出金额
     * @param poolFee 池费率
     * @param recipient 接收地址
     * @return amountOut 输出金额
     */
    function _executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24 poolFee,
        address recipient
    ) internal returns (uint256 amountOut) {
        // 授权给 Uniswap Router
        // 使用 forceApprove 设置精确的授权金额，避免累加
        IERC20(tokenIn).forceApprove(address(swapRouter), amountIn);

        // 构建兑换参数
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: poolFee,
            recipient: recipient,
            deadline: block.timestamp + SWAP_DEADLINE,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });

        // 执行兑换
        amountOut = swapRouter.exactInputSingle(params);
    }

    // ============ 价格监控函数 ============

    /**
     * @notice 检查价格异常并更新价格历史
     * @param strategyId 策略 ID
     * @param amountIn 输入金额
     * @param amountOut 输出金额
     * @return anomalyDetected 是否检测到价格异常
     *
     * 安全改进: 检测价格异常波动，自动暂停策略
     * 注意: 不会 revert，只会暂停策略，让当前交易完成
     */
    function _checkAndUpdatePrice(
        bytes32 strategyId,
        uint256 amountIn,
        uint256 amountOut
    ) internal returns (bool anomalyDetected) {
        // 计算当前价格 (18 位精度)
        uint256 currentPrice = (amountIn * 1e18) / amountOut;

        uint256 avgPrice = rollingAvgPrice[strategyId];

        // 如果不是第一次执行，检查价格偏差
        if (avgPrice > 0) {
            uint256 priceDeviation;
            if (currentPrice > avgPrice) {
                priceDeviation = ((currentPrice - avgPrice) * 100) / avgPrice;
            } else {
                priceDeviation = ((avgPrice - currentPrice) * 100) / avgPrice;
            }

            // 如果偏差超过阈值，暂停策略但不 revert
            // 让当前交易完成，但阻止后续执行
            if (priceDeviation > MAX_PRICE_DEVIATION) {
                DCAStrategy storage strategy = _strategies[strategyId];
                strategy.status = StrategyStatus.Paused;

                emit StrategyAutoPaused(
                    strategyId,
                    "Price anomaly detected",
                    avgPrice,
                    currentPrice,
                    priceDeviation
                );

                anomalyDetected = true;
                // 不更新价格历史，保留异常前的数据
                lastExecutionPrice[strategyId] = currentPrice;
                return anomalyDetected;
            }
        }

        // 更新价格历史 (使用指数移动平均)
        if (avgPrice == 0) {
            rollingAvgPrice[strategyId] = currentPrice;
        } else {
            // EMA: newAvg = oldAvg * 0.7 + currentPrice * 0.3
            rollingAvgPrice[strategyId] = (avgPrice * 70 + currentPrice * 30) / 100;
        }

        lastExecutionPrice[strategyId] = currentPrice;
        anomalyDetected = false;
    }

    // ============ 紧急函数 ============

    /**
     * @notice 提议紧急提取代币
     * @param token 代币地址
     * @param to 接收地址
     * @param amount 金额
     *
     * 安全改进: 添加 48 小时时间锁，防止私钥泄露后立即转走资金
     */
    function proposeEmergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        
        uint256 executeAfter = block.timestamp + EMERGENCY_WITHDRAW_DELAY;
        
        pendingWithdraw = PendingEmergencyWithdraw({
            token: token,
            to: to,
            amount: amount,
            executeAfter: executeAfter,
            pending: true
        });
        
        emit EmergencyWithdrawProposed(token, to, amount, executeAfter);
    }

    /**
     * @notice 执行紧急提取
     *
     * 要求: 必须等待时间锁到期
     */
    function executeEmergencyWithdraw() external onlyOwner {
        PendingEmergencyWithdraw memory withdraw = pendingWithdraw;
        
        require(withdraw.pending, "No pending withdrawal");
        require(block.timestamp >= withdraw.executeAfter, "Timelock not expired");
        
        IERC20(withdraw.token).safeTransfer(withdraw.to, withdraw.amount);
        
        delete pendingWithdraw;
        
        emit EmergencyWithdrawExecuted(withdraw.token, withdraw.to, withdraw.amount);
    }

    /**
     * @notice 取消紧急提取
     */
    function cancelEmergencyWithdraw() external onlyOwner {
        require(pendingWithdraw.pending, "No pending withdrawal");
        
        delete pendingWithdraw;
        
        emit EmergencyWithdrawCancelled();
    }

    /**
     * @notice 接收 ETH (用于 WETH 转换)
     */
    receive() external payable {}
}
