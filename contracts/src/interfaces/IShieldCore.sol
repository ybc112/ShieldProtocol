// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IShieldCore
 * @notice Shield Protocol 核心防护合约接口
 * @dev 定义了用户资产保护和限额管理的核心功能
 */
interface IShieldCore {
    // ============ 结构体 ============

    /// @notice 用户的 Shield 防护配置
    struct ShieldConfig {
        uint256 dailySpendLimit;      // 每日支出限额 (以 wei 为单位)
        uint256 singleTxLimit;        // 单笔交易限额
        uint256 spentToday;           // 今日已支出金额
        uint256 lastResetTimestamp;   // 上次重置时间戳
        bool isActive;                // 防护是否激活
        bool emergencyMode;           // 紧急模式是否开启
        bool whitelistEnabled;        // 白名单模式是否启用
    }

    /// @notice 代币支出限额配置
    struct TokenLimit {
        address token;                // 代币地址
        uint256 dailyLimit;           // 每日限额
        uint256 spentToday;           // 今日已支出
        uint256 lastResetTimestamp;   // 上次重置时间
    }

    // ============ 事件 ============

    /// @notice Shield 防护激活事件
    event ShieldActivated(
        address indexed user,
        uint256 dailyLimit,
        uint256 singleTxLimit,
        uint256 timestamp
    );

    /// @notice Shield 配置更新事件
    event ShieldConfigUpdated(
        address indexed user,
        uint256 newDailyLimit,
        uint256 newSingleTxLimit
    );

    /// @notice Shield 防护停用事件
    event ShieldDeactivated(address indexed user, uint256 timestamp);

    /// @notice 紧急模式启用事件
    event EmergencyModeEnabled(address indexed user, uint256 timestamp);

    /// @notice 紧急模式解除事件
    event EmergencyModeDisabled(address indexed user, uint256 timestamp);

    /// @notice 支出记录事件
    event SpendingRecorded(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 dailyTotal,
        uint256 timestamp
    );

    /// @notice 白名单合约添加事件
    event ContractWhitelisted(
        address indexed user,
        address indexed contractAddress
    );

    /// @notice 白名单合约移除事件
    event ContractRemovedFromWhitelist(
        address indexed user,
        address indexed contractAddress
    );

    /// @notice 每日限额重置事件
    event DailyLimitReset(address indexed user, uint256 timestamp);

    /// @notice 授权执行器添加事件
    event AuthorizedExecutorAdded(address indexed executor);

    /// @notice 授权执行器移除事件
    event AuthorizedExecutorRemoved(address indexed executor);

    /// @notice 协议暂停状态变更事件
    event ProtocolPausedChanged(bool paused);

    // ============ 错误 ============

    error ShieldNotActive();
    error ShieldAlreadyActive();
    error EmergencyModeActive();
    error ExceedsDailyLimit(uint256 requested, uint256 remaining);
    error ExceedsSingleTxLimit(uint256 requested, uint256 limit);
    error InvalidLimit();
    error ContractNotWhitelisted(address target);
    error Unauthorized();

    // ============ 函数 ============

    /// @notice 激活 Shield 防护
    /// @param dailyLimit 每日支出限额
    /// @param singleTxLimit 单笔交易限额
    function activateShield(uint256 dailyLimit, uint256 singleTxLimit) external;

    /// @notice 提议更新 Shield 配置 (需要冷却期)
    /// @param newDailyLimit 新的每日限额
    /// @param newSingleTxLimit 新的单笔限额
    function proposeShieldConfigUpdate(uint256 newDailyLimit, uint256 newSingleTxLimit) external;

    /// @notice 执行待生效的配置更新
    function executeShieldConfigUpdate() external;

    /// @notice 取消待生效的配置更新
    function cancelShieldConfigUpdate() external;

    /// @notice 停用 Shield 防护
    function deactivateShield() external;

    /// @notice 启用紧急模式
    function enableEmergencyMode() external;

    /// @notice 解除紧急模式
    function disableEmergencyMode() external;

    /// @notice 记录支出 (被策略执行器调用)
    /// @param user 用户地址
    /// @param token 代币地址
    /// @param amount 支出金额
    /// @dev 失败会直接 revert，不再返回 bool
    function recordSpending(
        address user,
        address token,
        uint256 amount
    ) external;

    /// @notice 检查支出是否允许 (不修改状态)
    /// @param user 用户地址
    /// @param token 代币地址
    /// @param amount 支出金额
    /// @return allowed 是否允许
    /// @return reason 如果不允许，返回原因
    function checkSpendingAllowed(
        address user,
        address token,
        uint256 amount
    ) external view returns (bool allowed, string memory reason);

    /// @notice 启用白名单模式
    function enableWhitelistMode() external;

    /// @notice 禁用白名单模式
    function disableWhitelistMode() external;

    /// @notice 添加白名单合约
    /// @param contractAddress 合约地址
    function addWhitelistedContract(address contractAddress) external;

    /// @notice 移除白名单合约
    /// @param contractAddress 合约地址
    function removeWhitelistedContract(address contractAddress) external;

    /// @notice 检查合约是否在白名单中
    /// @param user 用户地址
    /// @param contractAddress 合约地址
    /// @return 是否在白名单中
    function isWhitelisted(address user, address contractAddress) external view returns (bool);

    /// @notice 获取用户的 Shield 配置
    /// @param user 用户地址
    /// @return config Shield 配置
    function getShieldConfig(address user) external view returns (ShieldConfig memory config);

    /// @notice 获取用户今日剩余额度
    /// @param user 用户地址
    /// @param token 代币地址 (address(0) 表示原生代币)
    /// @return remaining 剩余额度
    function getRemainingDailyAllowance(
        address user,
        address token
    ) external view returns (uint256 remaining);

    /// @notice 获取用户的白名单合约列表
    /// @param user 用户地址
    /// @return contracts 白名单合约地址数组
    function getWhitelistedContracts(address user) external view returns (address[] memory contracts);
}
