// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IRebalanceExecutor
 * @notice 投资组合再平衡执行器接口
 * @dev 定义了再平衡策略的创建、执行和管理功能
 */
interface IRebalanceExecutor {
    // ============ 枚举 ============

    /// @notice 策略状态
    enum StrategyStatus {
        Active,     // 活跃中
        Paused,     // 已暂停
        Cancelled   // 已取消
    }

    // ============ 结构体 ============

    /// @notice 资产配置
    struct AssetAllocation {
        address token;          // 代币地址
        uint256 targetWeight;   // 目标权重 (基点, 10000 = 100%)
        uint256 currentWeight;  // 当前权重
    }

    /// @notice 再平衡策略
    struct RebalanceStrategy {
        address user;                   // 策略所有者
        AssetAllocation[] allocations;  // 资产配置列表
        uint256 rebalanceThreshold;     // 再平衡阈值 (基点, 如 500 = 5%)
        uint256 minRebalanceInterval;   // 最小再平衡间隔 (秒)
        uint256 lastRebalanceTime;      // 上次再平衡时间
        uint256 totalRebalances;        // 总再平衡次数
        uint24 poolFee;                 // Uniswap 池费率
        StrategyStatus status;          // 策略状态
        uint256 createdAt;              // 创建时间
        uint256 updatedAt;              // 更新时间
    }

    /// @notice 创建策略参数
    struct CreateStrategyParams {
        address[] tokens;           // 代币地址列表
        uint256[] targetWeights;    // 目标权重列表 (基点)
        uint256 rebalanceThreshold; // 再平衡阈值 (基点)
        uint256 minRebalanceInterval; // 最小再平衡间隔 (秒)
        uint24 poolFee;             // Uniswap 池费率
    }

    /// @notice 再平衡记录
    struct RebalanceRecord {
        bytes32 strategyId;         // 策略 ID
        uint256 timestamp;          // 执行时间
        uint256 totalValueBefore;   // 再平衡前总价值
        uint256 totalValueAfter;    // 再平衡后总价值
        uint256 gasUsed;            // 消耗的 Gas
    }

    // ============ 事件 ============

    /// @notice 策略创建事件
    event StrategyCreated(
        bytes32 indexed strategyId,
        address indexed user,
        address[] tokens,
        uint256[] targetWeights,
        uint256 rebalanceThreshold
    );

    /// @notice 再平衡执行事件
    event RebalanceExecuted(
        bytes32 indexed strategyId,
        address indexed user,
        uint256 totalValue,
        uint256 rebalanceNumber,
        uint256 timestamp
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
        uint256[] newTargetWeights,
        uint256 newThreshold
    );

    // ============ 错误 ============

    error StrategyNotFound();
    error StrategyNotActive();
    error NotStrategyOwner();
    error InvalidParameters();
    error RebalanceNotNeeded();
    error RebalanceTooSoon(uint256 nextAllowedTime);
    error WeightsSumInvalid();
    error InsufficientBalance();
    error SlippageExceeded(uint256 expected, uint256 actual);

    // ============ 函数 ============

    /// @notice 创建再平衡策略
    function createStrategy(
        CreateStrategyParams calldata params
    ) external returns (bytes32 strategyId);

    /// @notice 执行再平衡
    function executeRebalance(bytes32 strategyId) external;

    /// @notice 暂停策略
    function pauseStrategy(bytes32 strategyId) external;

    /// @notice 恢复策略
    function resumeStrategy(bytes32 strategyId) external;

    /// @notice 取消策略
    function cancelStrategy(bytes32 strategyId) external;

    /// @notice 更新策略参数
    function updateStrategy(
        bytes32 strategyId,
        uint256[] calldata newTargetWeights,
        uint256 newThreshold
    ) external;

    /// @notice 获取策略详情
    function getStrategy(bytes32 strategyId) external view returns (RebalanceStrategy memory);

    /// @notice 获取用户的所有策略 ID
    function getUserStrategies(address user) external view returns (bytes32[] memory);

    /// @notice 检查是否需要再平衡
    function needsRebalance(bytes32 strategyId) external view returns (bool needed, string memory reason);

    /// @notice 获取当前资产权重
    function getCurrentWeights(bytes32 strategyId) external view returns (uint256[] memory weights);

    /// @notice 获取投资组合总价值
    function getPortfolioValue(bytes32 strategyId) external view returns (uint256 totalValue);

    /// @notice 获取再平衡历史
    function getRebalanceHistory(bytes32 strategyId) external view returns (RebalanceRecord[] memory);
}
