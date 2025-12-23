// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IShieldCore} from "../interfaces/IShieldCore.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title ShieldCore
 * @author Shield Protocol Team
 * @notice 核心资产保护合约，管理用户的安全配置和支出限额
 * @dev 实现了细粒度的权限控制和支出追踪
 *
 * 核心功能:
 * 1. 用户可以设置每日/单笔支出限额
 * 2. 记录和追踪每日支出
 * 3. 白名单合约管理
 * 4. 紧急模式一键冻结
 *
 * 设计原理:
 * - 每个用户有独立的 ShieldConfig 配置
 * - 支出限额按代币分别追踪
 * - 每日 0:00 UTC 自动重置计数
 * - 紧急模式下拒绝所有支出
 */
contract ShieldCore is IShieldCore, Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    // ============ 常量 ============

    /// @notice 一天的秒数
    uint256 public constant SECONDS_PER_DAY = 86400;

    /// @notice 最小每日限额 (防止设置为 0)
    uint256 public constant MIN_DAILY_LIMIT = 1e6; // 1 USDC (6 decimals)

    /// @notice 原生代币地址标识
    address public constant NATIVE_TOKEN = address(0);

    // ============ 状态变量 ============

    /// @notice 用户地址 => Shield 配置
    mapping(address => ShieldConfig) private _shields;

    /// @notice 用户地址 => 代币地址 => 代币限额配置
    mapping(address => mapping(address => TokenLimit)) private _tokenLimits;

    /// @notice 用户地址 => 白名单合约集合
    mapping(address => EnumerableSet.AddressSet) private _whitelistedContracts;

    /// @notice 授权的执行器合约 (DCAExecutor, SubscriptionManager 等)
    mapping(address => bool) public authorizedExecutors;

    /// @notice 协议暂停状态
    bool public protocolPaused;

    // ============ 修饰符 ============

    /// @notice 确保 Shield 已激活
    modifier onlyActiveShield(address user) {
        if (!_shields[user].isActive) revert ShieldNotActive();
        if (_shields[user].emergencyMode) revert EmergencyModeActive();
        _;
    }

    /// @notice 确保协议未暂停
    modifier whenNotPaused() {
        require(!protocolPaused, "Protocol paused");
        _;
    }

    /// @notice 确保是授权的执行器
    modifier onlyAuthorizedExecutor() {
        require(authorizedExecutors[msg.sender], "Not authorized executor");
        _;
    }

    // ============ 构造函数 ============

    constructor() Ownable(msg.sender) {}

    // ============ 管理函数 ============

    /// @notice 添加授权执行器
    /// @param executor 执行器地址
    function addAuthorizedExecutor(address executor) external onlyOwner {
        require(executor != address(0), "Invalid executor");
        authorizedExecutors[executor] = true;
        emit AuthorizedExecutorAdded(executor);
    }

    /// @notice 移除授权执行器
    /// @param executor 执行器地址
    function removeAuthorizedExecutor(address executor) external onlyOwner {
        authorizedExecutors[executor] = false;
        emit AuthorizedExecutorRemoved(executor);
    }

    /// @notice 暂停/恢复协议
    /// @param paused 是否暂停
    function setProtocolPaused(bool paused) external onlyOwner {
        protocolPaused = paused;
        emit ProtocolPausedChanged(paused);
    }

    // ============ Shield 管理函数 ============

    /**
     * @notice 激活 Shield 防护
     * @param dailyLimit 每日支出限额
     * @param singleTxLimit 单笔交易限额
     *
     * 设计考虑:
     * - 要求最小限额防止误操作
     * - 单笔限额不能超过每日限额
     * - 激活后立即生效
     */
    function activateShield(
        uint256 dailyLimit,
        uint256 singleTxLimit
    ) external whenNotPaused {
        if (_shields[msg.sender].isActive) revert ShieldAlreadyActive();
        if (dailyLimit < MIN_DAILY_LIMIT) revert InvalidLimit();
        if (singleTxLimit > dailyLimit) revert InvalidLimit();
        if (singleTxLimit == 0) revert InvalidLimit();

        _shields[msg.sender] = ShieldConfig({
            dailySpendLimit: dailyLimit,
            singleTxLimit: singleTxLimit,
            spentToday: 0,
            lastResetTimestamp: _getCurrentDayStart(),
            isActive: true,
            emergencyMode: false
        });

        emit ShieldActivated(msg.sender, dailyLimit, singleTxLimit, block.timestamp);
    }

    /**
     * @notice 更新 Shield 配置
     * @param newDailyLimit 新的每日限额
     * @param newSingleTxLimit 新的单笔限额
     *
     * 注意: 更新立即生效，不影响今日已用额度
     */
    function updateShieldConfig(
        uint256 newDailyLimit,
        uint256 newSingleTxLimit
    ) external onlyActiveShield(msg.sender) {
        if (newDailyLimit < MIN_DAILY_LIMIT) revert InvalidLimit();
        if (newSingleTxLimit > newDailyLimit) revert InvalidLimit();
        if (newSingleTxLimit == 0) revert InvalidLimit();

        ShieldConfig storage config = _shields[msg.sender];
        config.dailySpendLimit = newDailyLimit;
        config.singleTxLimit = newSingleTxLimit;

        emit ShieldConfigUpdated(msg.sender, newDailyLimit, newSingleTxLimit);
    }

    /**
     * @notice 停用 Shield 防护
     *
     * 警告: 停用后将失去所有保护
     */
    function deactivateShield() external {
        if (!_shields[msg.sender].isActive) revert ShieldNotActive();

        _shields[msg.sender].isActive = false;

        emit ShieldDeactivated(msg.sender, block.timestamp);
    }

    /**
     * @notice 启用紧急模式
     *
     * 效果:
     * - 立即阻止所有自动执行
     * - 不会自动恢复，需要手动解除
     * - 用于发现可疑活动时紧急保护
     */
    function enableEmergencyMode() external {
        if (!_shields[msg.sender].isActive) revert ShieldNotActive();

        _shields[msg.sender].emergencyMode = true;

        emit EmergencyModeEnabled(msg.sender, block.timestamp);
    }

    /**
     * @notice 解除紧急模式
     */
    function disableEmergencyMode() external {
        if (!_shields[msg.sender].isActive) revert ShieldNotActive();
        if (!_shields[msg.sender].emergencyMode) revert("Not in emergency mode");

        _shields[msg.sender].emergencyMode = false;

        emit EmergencyModeDisabled(msg.sender, block.timestamp);
    }

    // ============ 支出追踪函数 ============

    /**
     * @notice 记录支出
     * @param user 用户地址
     * @param token 代币地址 (address(0) 表示原生代币)
     * @param amount 支出金额
     * @return success 是否成功记录
     *
     * 执行流程:
     * 1. 检查 Shield 是否激活且非紧急模式
     * 2. 检查单笔限额
     * 3. 检查并重置每日计数 (如果跨天)
     * 4. 检查每日限额
     * 5. 记录支出
     *
     * 权限: 只有授权执行器可调用
     */
    function recordSpending(
        address user,
        address token,
        uint256 amount
    ) external onlyAuthorizedExecutor nonReentrant returns (bool success) {
        // 检查 Shield 状态
        ShieldConfig storage config = _shields[user];
        if (!config.isActive) revert ShieldNotActive();
        if (config.emergencyMode) revert EmergencyModeActive();

        // 检查单笔限额
        if (amount > config.singleTxLimit) {
            revert ExceedsSingleTxLimit(amount, config.singleTxLimit);
        }

        // 检查是否需要重置每日计数
        uint256 currentDayStart = _getCurrentDayStart();
        if (config.lastResetTimestamp < currentDayStart) {
            config.spentToday = 0;
            config.lastResetTimestamp = currentDayStart;
            emit DailyLimitReset(user, currentDayStart);
        }

        // 检查每日限额
        uint256 remaining = config.dailySpendLimit - config.spentToday;
        if (amount > remaining) {
            revert ExceedsDailyLimit(amount, remaining);
        }

        // 记录支出
        config.spentToday += amount;

        // 如果配置了代币特定限额，也记录
        if (_tokenLimits[user][token].dailyLimit > 0) {
            _recordTokenSpending(user, token, amount);
        }

        emit SpendingRecorded(user, token, amount, config.spentToday, block.timestamp);

        return true;
    }

    /**
     * @notice 检查支出是否允许 (不修改状态)
     * @param user 用户地址
     * @param token 代币地址
     * @param amount 支出金额
     * @return allowed 是否允许
     * @return reason 如果不允许，返回原因
     */
    function checkSpendingAllowed(
        address user,
        address token,
        uint256 amount
    ) external view returns (bool allowed, string memory reason) {
        ShieldConfig memory config = _shields[user];

        if (!config.isActive) {
            return (false, "Shield not active");
        }

        if (config.emergencyMode) {
            return (false, "Emergency mode enabled");
        }

        if (amount > config.singleTxLimit) {
            return (false, "Exceeds single transaction limit");
        }

        // 计算实际剩余额度 (考虑跨天重置)
        uint256 currentDayStart = _getCurrentDayStart();
        uint256 spentToday = config.lastResetTimestamp < currentDayStart ? 0 : config.spentToday;
        uint256 remaining = config.dailySpendLimit - spentToday;

        if (amount > remaining) {
            return (false, "Exceeds daily limit");
        }

        // 检查代币特定限额
        TokenLimit memory tokenLimit = _tokenLimits[user][token];
        if (tokenLimit.dailyLimit > 0) {
            uint256 tokenSpentToday = tokenLimit.lastResetTimestamp < currentDayStart
                ? 0
                : tokenLimit.spentToday;
            uint256 tokenRemaining = tokenLimit.dailyLimit - tokenSpentToday;
            if (amount > tokenRemaining) {
                return (false, "Exceeds token daily limit");
            }
        }

        return (true, "");
    }

    /**
     * @notice 记录代币特定的支出
     */
    function _recordTokenSpending(
        address user,
        address token,
        uint256 amount
    ) internal {
        TokenLimit storage limit = _tokenLimits[user][token];

        uint256 currentDayStart = _getCurrentDayStart();
        if (limit.lastResetTimestamp < currentDayStart) {
            limit.spentToday = 0;
            limit.lastResetTimestamp = currentDayStart;
        }

        require(
            limit.spentToday + amount <= limit.dailyLimit,
            "Token daily limit exceeded"
        );

        limit.spentToday += amount;
    }

    // ============ 白名单管理 ============

    /**
     * @notice 添加白名单合约
     * @param contractAddress 合约地址
     *
     * 用途: 限制只能与信任的合约交互
     */
    function addWhitelistedContract(address contractAddress) external onlyActiveShield(msg.sender) {
        require(contractAddress != address(0), "Invalid address");
        require(contractAddress.code.length > 0, "Not a contract");

        _whitelistedContracts[msg.sender].add(contractAddress);

        emit ContractWhitelisted(msg.sender, contractAddress);
    }

    /**
     * @notice 移除白名单合约
     * @param contractAddress 合约地址
     */
    function removeWhitelistedContract(address contractAddress) external {
        _whitelistedContracts[msg.sender].remove(contractAddress);

        emit ContractRemovedFromWhitelist(msg.sender, contractAddress);
    }

    /**
     * @notice 检查合约是否在白名单中
     * @param user 用户地址
     * @param contractAddress 合约地址
     */
    function isWhitelisted(address user, address contractAddress) external view returns (bool) {
        // 如果用户没有设置白名单，默认允许所有
        if (_whitelistedContracts[user].length() == 0) {
            return true;
        }
        return _whitelistedContracts[user].contains(contractAddress);
    }

    // ============ 代币限额管理 ============

    /**
     * @notice 设置代币特定的每日限额
     * @param token 代币地址
     * @param dailyLimit 每日限额
     */
    function setTokenLimit(address token, uint256 dailyLimit) external onlyActiveShield(msg.sender) {
        _tokenLimits[msg.sender][token] = TokenLimit({
            token: token,
            dailyLimit: dailyLimit,
            spentToday: 0,
            lastResetTimestamp: _getCurrentDayStart()
        });
    }

    /**
     * @notice 移除代币特定限额
     * @param token 代币地址
     */
    function removeTokenLimit(address token) external {
        delete _tokenLimits[msg.sender][token];
    }

    // ============ 视图函数 ============

    /**
     * @notice 获取用户的 Shield 配置
     * @param user 用户地址
     */
    function getShieldConfig(address user) external view returns (ShieldConfig memory config) {
        return _shields[user];
    }

    /**
     * @notice 获取用户今日剩余额度
     * @param user 用户地址
     * @param token 代币地址 (address(0) 表示全局限额)
     */
    function getRemainingDailyAllowance(
        address user,
        address token
    ) external view returns (uint256 remaining) {
        ShieldConfig memory config = _shields[user];
        if (!config.isActive) return 0;

        // 检查是否跨天
        uint256 currentDayStart = _getCurrentDayStart();

        // 全局剩余额度
        uint256 globalSpentToday = config.lastResetTimestamp < currentDayStart ? 0 : config.spentToday;
        uint256 globalRemaining = config.dailySpendLimit - globalSpentToday;

        // 如果有代币特定限额，返回较小值
        TokenLimit memory tokenLimit = _tokenLimits[user][token];
        if (tokenLimit.dailyLimit > 0) {
            uint256 tokenSpentToday = tokenLimit.lastResetTimestamp < currentDayStart ? 0 : tokenLimit.spentToday;
            uint256 tokenRemaining = tokenLimit.dailyLimit - tokenSpentToday;
            return tokenRemaining < globalRemaining ? tokenRemaining : globalRemaining;
        }

        return globalRemaining;
    }

    /**
     * @notice 获取用户的白名单合约列表
     * @param user 用户地址
     */
    function getWhitelistedContracts(address user) external view returns (address[] memory contracts) {
        uint256 length = _whitelistedContracts[user].length();
        contracts = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            contracts[i] = _whitelistedContracts[user].at(i);
        }
        return contracts;
    }

    /**
     * @notice 获取代币特定限额配置
     * @param user 用户地址
     * @param token 代币地址
     */
    function getTokenLimit(address user, address token) external view returns (TokenLimit memory) {
        return _tokenLimits[user][token];
    }

    // ============ 内部函数 ============

    /**
     * @notice 获取当天 0:00 UTC 的时间戳
     * @return dayStart 当天开始的时间戳
     */
    function _getCurrentDayStart() internal view returns (uint256 dayStart) {
        return (block.timestamp / SECONDS_PER_DAY) * SECONDS_PER_DAY;
    }
}
