// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IDCAExecutor
 * @notice DCA (Dollar Cost Averaging) 策略执行器接口
 * @dev 定义了 DCA 定投策略的创建、执行和管理功能
 */
interface IDCAExecutor {
    // ============ 枚举 ============

    /// @notice 策略状态
    enum StrategyStatus {
        Active,      // 活跃中
        Paused,      // 已暂停
        Completed,   // 已完成
        Cancelled    // 已取消
    }

    // ============ 结构体 ============

    /// @notice DCA 策略配置
    struct DCAStrategy {
        address user;                  // 策略所有者
        address sourceToken;           // 源代币地址 (用于支付)
        address targetToken;           // 目标代币地址 (想要购买的)
        uint256 amountPerExecution;    // 每次执行金额
        uint256 minAmountOut;          // 最小输出金额 (滑点保护)
        uint256 intervalSeconds;       // 执行间隔 (秒)
        uint256 nextExecutionTime;     // 下次执行时间
        uint256 totalExecutions;       // 总执行次数
        uint256 executionsCompleted;   // 已完成执行次数
        uint24 poolFee;                // Uniswap 池费率
        StrategyStatus status;         // 策略状态
        uint256 createdAt;             // 创建时间
        uint256 updatedAt;             // 最后更新时间
    }

    /// @notice 策略执行记录
    struct ExecutionRecord {
        bytes32 strategyId;            // 策略 ID
        uint256 amountIn;              // 输入金额
        uint256 amountOut;             // 输出金额
        uint256 executionPrice;        // 执行价格
        uint256 gasUsed;               // 消耗的 Gas
        uint256 timestamp;             // 执行时间
    }

    /// @notice 创建策略的参数
    struct CreateStrategyParams {
        address sourceToken;
        address targetToken;
        uint256 amountPerExecution;
        uint256 minAmountOut;
        uint256 intervalSeconds;
        uint256 totalExecutions;
        uint24 poolFee;
    }

    // ============ 事件 ============

    /// @notice 策略创建事件
    event StrategyCreated(
        bytes32 indexed strategyId,
        address indexed user,
        address sourceToken,
        address targetToken,
        uint256 amountPerExecution,
        uint256 intervalSeconds,
        uint256 totalExecutions
    );

    /// @notice DCA 执行事件
    event DCAExecuted(
        bytes32 indexed strategyId,
        address indexed user,
        uint256 amountIn,
        uint256 amountOut,
        uint256 executionNumber,
        uint256 timestamp
    );

    /// @notice 策略暂停事件
    event StrategyPaused(bytes32 indexed strategyId, uint256 timestamp);

    /// @notice 策略恢复事件
    event StrategyResumed(bytes32 indexed strategyId, uint256 timestamp);

    /// @notice 策略取消事件
    event StrategyCancelled(bytes32 indexed strategyId, uint256 timestamp);

    /// @notice 策略完成事件
    event StrategyCompleted(
        bytes32 indexed strategyId,
        uint256 totalAmountIn,
        uint256 totalAmountOut
    );

    /// @notice 策略参数更新事件
    event StrategyUpdated(
        bytes32 indexed strategyId,
        uint256 newAmountPerExecution,
        uint256 newMinAmountOut
    );

    /// @notice 策略因价格异常自动暂停
    event StrategyAutoPaused(
        bytes32 indexed strategyId,
        string reason,
        uint256 avgPrice,
        uint256 currentPrice,
        uint256 deviation
    );

    /// @notice 紧急提币提议
    event EmergencyWithdrawProposed(
        address indexed token,
        address indexed to,
        uint256 amount,
        uint256 executeAfter
    );

    /// @notice 紧急提币执行
    event EmergencyWithdrawExecuted(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    /// @notice 紧急提币取消
    event EmergencyWithdrawCancelled();

    // ============ 错误 ============

    error StrategyNotFound();
    error StrategyNotActive();
    error StrategyAlreadyCompleted();
    error NotStrategyOwner();
    error ExecutionTooEarly(uint256 nextExecutionTime);
    error InsufficientBalance();
    error InsufficientAllowance();
    error SlippageExceeded(uint256 expected, uint256 actual);
    error InvalidParameters();
    error PriceAnomalyDetected(uint256 avgPrice, uint256 currentPrice, uint256 deviation);
    // 注意: ShieldCore 的限额错误 (ExceedsDailyLimit, ExceedsSingleTxLimit) 会直接冒泡

    // ============ 函数 ============

    /// @notice 创建 DCA 策略
    /// @param params 策略参数
    /// @return strategyId 策略 ID
    function createStrategy(
        CreateStrategyParams calldata params
    ) external returns (bytes32 strategyId);

    /// @notice 执行 DCA 策略
    /// @param strategyId 策略 ID
    /// @return amountOut 输出金额
    function executeDCA(bytes32 strategyId) external returns (uint256 amountOut);

    /// @notice 批量执行多个策略
    /// @param strategyIds 策略 ID 数组
    /// @return results 每个策略的执行结果
    function batchExecuteDCA(
        bytes32[] calldata strategyIds
    ) external returns (uint256[] memory results);

    /// @notice 暂停策略
    /// @param strategyId 策略 ID
    function pauseStrategy(bytes32 strategyId) external;

    /// @notice 恢复策略
    /// @param strategyId 策略 ID
    function resumeStrategy(bytes32 strategyId) external;

    /// @notice 取消策略
    /// @param strategyId 策略 ID
    function cancelStrategy(bytes32 strategyId) external;

    /// @notice 更新策略参数
    /// @param strategyId 策略 ID
    /// @param newAmountPerExecution 新的每次执行金额
    /// @param newMinAmountOut 新的最小输出金额
    function updateStrategy(
        bytes32 strategyId,
        uint256 newAmountPerExecution,
        uint256 newMinAmountOut
    ) external;

    /// @notice 获取策略详情
    /// @param strategyId 策略 ID
    /// @return strategy 策略详情
    function getStrategy(bytes32 strategyId) external view returns (DCAStrategy memory strategy);

    /// @notice 获取用户的所有策略 ID
    /// @param user 用户地址
    /// @return strategyIds 策略 ID 数组
    function getUserStrategies(address user) external view returns (bytes32[] memory strategyIds);

    /// @notice 获取待执行的策略 (支持分页)
    /// @param startIndex 起始索引
    /// @param limit 返回数量限制
    /// @return strategyIds 待执行的策略 ID 数组
    /// @return nextIndex 下一个起始索引 (0 表示结束)
    function getPendingStrategies(uint256 startIndex, uint256 limit) external view returns (bytes32[] memory strategyIds, uint256 nextIndex);

    /// @notice 检查策略是否可执行
    /// @param strategyId 策略 ID
    /// @return canExecute 是否可执行
    /// @return reason 如果不可执行，返回原因
    function canExecute(bytes32 strategyId) external view returns (bool canExecute, string memory reason);

    /// @notice 获取策略的执行历史
    /// @param strategyId 策略 ID
    /// @return records 执行记录数组
    function getExecutionHistory(
        bytes32 strategyId
    ) external view returns (ExecutionRecord[] memory records);

    /// @notice 计算策略的平均购买价格
    /// @param strategyId 策略 ID
    /// @return averagePrice 平均价格
    function getAveragePrice(bytes32 strategyId) external view returns (uint256 averagePrice);
}
