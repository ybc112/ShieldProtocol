// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IStopLossExecutor
 * @notice 止损保护执行器接口
 * @dev 定义了止损策略的创建、执行和管理功能
 */
interface IStopLossExecutor {
    // ============ 枚举 ============

    /// @notice 策略状态
    enum StrategyStatus {
        Active,     // 监控中
        Triggered,  // 已触发
        Paused,     // 已暂停
        Cancelled   // 已取消
    }

    /// @notice 止损类型
    enum StopLossType {
        FixedPrice,     // 固定价格止损
        Percentage,     // 百分比止损
        TrailingStop    // 追踪止损
    }

    // ============ 结构体 ============

    /// @notice 止损策略
    struct StopLossStrategy {
        address user;               // 策略所有者
        address tokenToSell;        // 要卖出的代币
        address tokenToReceive;     // 接收的代币 (通常是稳定币)
        uint256 amount;             // 要卖出的数量
        StopLossType stopLossType;  // 止损类型
        uint256 triggerPrice;       // 触发价格 (对于固定价格)
        uint256 triggerPercentage;  // 触发百分比 (基点, 1000 = 10%)
        uint256 trailingDistance;   // 追踪距离 (基点)
        uint256 highestPrice;       // 历史最高价 (用于追踪止损)
        uint256 minAmountOut;       // 最小输出金额
        uint24 poolFee;             // Uniswap 池费率
        StrategyStatus status;      // 策略状态
        uint256 createdAt;          // 创建时间
        uint256 triggeredAt;        // 触发时间
        uint256 executedAmount;     // 已执行金额
    }

    /// @notice 创建策略参数
    struct CreateStrategyParams {
        address tokenToSell;        // 要卖出的代币
        address tokenToReceive;     // 接收的代币
        uint256 amount;             // 要卖出的数量
        StopLossType stopLossType;  // 止损类型
        uint256 triggerValue;       // 触发值 (价格或百分比，取决于类型)
        uint256 trailingDistance;   // 追踪距离 (仅追踪止损使用)
        uint256 minAmountOut;       // 最小输出金额
        uint24 poolFee;             // Uniswap 池费率
    }

    /// @notice 执行记录
    struct ExecutionRecord {
        bytes32 strategyId;         // 策略 ID
        uint256 amountSold;         // 卖出金额
        uint256 amountReceived;     // 收到金额
        uint256 executionPrice;     // 执行价格
        uint256 timestamp;          // 执行时间
    }

    // ============ 事件 ============

    /// @notice 策略创建事件
    event StrategyCreated(
        bytes32 indexed strategyId,
        address indexed user,
        address tokenToSell,
        address tokenToReceive,
        uint256 amount,
        StopLossType stopLossType,
        uint256 triggerValue
    );

    /// @notice 止损触发事件
    event StopLossTriggered(
        bytes32 indexed strategyId,
        address indexed user,
        uint256 currentPrice,
        uint256 triggerPrice,
        uint256 timestamp
    );

    /// @notice 止损执行事件
    event StopLossExecuted(
        bytes32 indexed strategyId,
        address indexed user,
        uint256 amountSold,
        uint256 amountReceived,
        uint256 executionPrice,
        uint256 timestamp
    );

    /// @notice 最高价更新事件 (追踪止损)
    event HighestPriceUpdated(
        bytes32 indexed strategyId,
        uint256 oldHighest,
        uint256 newHighest
    );

    /// @notice 策略暂停事件
    event StrategyPaused(bytes32 indexed strategyId, uint256 timestamp);

    /// @notice 策略恢复事件
    event StrategyResumed(bytes32 indexed strategyId, uint256 timestamp);

    /// @notice 策略取消事件
    event StrategyCancelled(bytes32 indexed strategyId, uint256 timestamp);

    /// @notice 策略更新事件
    event StrategyUpdated(
        bytes32 indexed strategyId,
        uint256 newTriggerValue,
        uint256 newMinAmountOut
    );

    // ============ 错误 ============

    error StrategyNotFound();
    error StrategyNotActive();
    error StrategyAlreadyTriggered();
    error NotStrategyOwner();
    error InvalidParameters();
    error StopLossNotTriggered();
    error InsufficientBalance();
    error InsufficientAllowance();
    error SlippageExceeded(uint256 expected, uint256 actual);

    // ============ 函数 ============

    /// @notice 创建止损策略
    function createStrategy(
        CreateStrategyParams calldata params
    ) external returns (bytes32 strategyId);

    /// @notice 检查并执行止损 (由 Keeper 调用)
    function checkAndExecute(bytes32 strategyId) external returns (bool executed);

    /// @notice 批量检查并执行
    function batchCheckAndExecute(bytes32[] calldata strategyIds) external returns (uint256 executedCount);

    /// @notice 更新最高价 (追踪止损)
    function updateHighestPrice(bytes32 strategyId, uint256 currentPrice) external;

    /// @notice 暂停策略
    function pauseStrategy(bytes32 strategyId) external;

    /// @notice 恢复策略
    function resumeStrategy(bytes32 strategyId) external;

    /// @notice 取消策略
    function cancelStrategy(bytes32 strategyId) external;

    /// @notice 更新策略参数
    function updateStrategy(
        bytes32 strategyId,
        uint256 newTriggerValue,
        uint256 newMinAmountOut
    ) external;

    /// @notice 获取策略详情
    function getStrategy(bytes32 strategyId) external view returns (StopLossStrategy memory);

    /// @notice 获取用户的所有策略 ID
    function getUserStrategies(address user) external view returns (bytes32[] memory);

    /// @notice 检查止损是否应该触发
    function shouldTrigger(bytes32 strategyId) external view returns (bool triggered, uint256 currentPrice);

    /// @notice 获取当前触发价格 (考虑追踪止损)
    function getCurrentTriggerPrice(bytes32 strategyId) external view returns (uint256);

    /// @notice 获取待触发的策略
    function getPendingStrategies(uint256 limit) external view returns (bytes32[] memory);

    /// @notice 获取执行历史
    function getExecutionHistory(bytes32 strategyId) external view returns (ExecutionRecord[] memory);
}
