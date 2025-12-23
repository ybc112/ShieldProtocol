// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICaveatEnforcer} from "../interfaces/ICaveatEnforcer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SpendingLimitEnforcer
 * @author Shield Protocol Team
 * @notice 支出限额 Caveat 执行器
 * @dev 限制单次/每日/总计支出金额
 *
 * 功能:
 * 1. 单笔交易金额限制
 * 2. 每日支出限额 (自动重置)
 * 3. 总计支出限额
 * 4. 支持多种代币
 *
 * Terms 编码格式:
 * - token: address - 代币地址
 * - singleTxLimit: uint256 - 单笔限额
 * - dailyLimit: uint256 - 每日限额
 * - totalLimit: uint256 - 总计限额
 */
contract SpendingLimitEnforcer is ICaveatEnforcer, Ownable {
    // ============ 结构体 ============

    /// @notice 限额配置
    struct LimitTerms {
        address token;          // 代币地址
        uint256 singleTxLimit;  // 单笔限额
        uint256 dailyLimit;     // 每日限额
        uint256 totalLimit;     // 总计限额
    }

    /// @notice 使用状态
    struct UsageState {
        uint256 spentToday;     // 今日已支出
        uint256 totalSpent;     // 总计已支出
        uint256 lastResetDay;   // 上次重置日期
    }

    // ============ 常量 ============

    uint256 public constant SECONDS_PER_DAY = 86400;

    // ============ 状态变量 ============

    /// @notice 授权的 DelegationManager 地址
    mapping(address => bool) public authorizedCallers;

    /// @notice delegationHash => UsageState
    mapping(bytes32 => UsageState) public usageStates;

    // ============ 事件 ============

    event AuthorizedCallerAdded(address indexed caller);
    event AuthorizedCallerRemoved(address indexed caller);

    event SpendingRecorded(
        bytes32 indexed delegationHash,
        address indexed token,
        uint256 amount,
        uint256 dailyTotal,
        uint256 totalSpent
    );

    event DailyLimitReset(bytes32 indexed delegationHash, uint256 timestamp);

    // ============ 错误 ============

    error ExceedsSingleTxLimit(uint256 requested, uint256 limit);
    error ExceedsDailyLimit(uint256 requested, uint256 remaining);
    error ExceedsTotalLimit(uint256 requested, uint256 remaining);
    error InvalidTerms();
    error InvalidArgs();
    error UnauthorizedCaller();

    // ============ 修饰符 ============

    modifier onlyAuthorizedCaller() {
        if (!authorizedCallers[msg.sender]) revert UnauthorizedCaller();
        _;
    }

    // ============ 构造函数 ============

    constructor() Ownable(msg.sender) {}

    // ============ 管理函数 ============

    /// @notice 添加授权调用者
    function addAuthorizedCaller(address caller) external onlyOwner {
        authorizedCallers[caller] = true;
        emit AuthorizedCallerAdded(caller);
    }

    /// @notice 移除授权调用者
    function removeAuthorizedCaller(address caller) external onlyOwner {
        authorizedCallers[caller] = false;
        emit AuthorizedCallerRemoved(caller);
    }

    // ============ Caveat 执行函数 ============

    /**
     * @notice 执行前验证
     * @dev 检查支出是否在限额范围内
     */
    function beforeHook(
        bytes calldata terms,
        bytes calldata args,
        uint8 mode,
        bytes calldata executionCalldata,
        bytes32 delegationHash,
        address delegator,
        address redeemer
    ) external override onlyAuthorizedCaller {
        // 解码限额配置
        LimitTerms memory limitTerms = _decodeTerms(terms);

        // 从 args 获取支出金额
        uint256 amount = _extractAmount(args, executionCalldata);

        // 获取使用状态
        UsageState storage state = usageStates[delegationHash];

        // 检查是否需要重置每日计数
        uint256 currentDay = block.timestamp / SECONDS_PER_DAY;
        if (state.lastResetDay < currentDay) {
            state.spentToday = 0;
            state.lastResetDay = currentDay;
            emit DailyLimitReset(delegationHash, block.timestamp);
        }

        // 检查单笔限额
        if (limitTerms.singleTxLimit > 0 && amount > limitTerms.singleTxLimit) {
            revert ExceedsSingleTxLimit(amount, limitTerms.singleTxLimit);
        }

        // 检查每日限额
        if (limitTerms.dailyLimit > 0) {
            uint256 dailyRemaining = limitTerms.dailyLimit - state.spentToday;
            if (amount > dailyRemaining) {
                revert ExceedsDailyLimit(amount, dailyRemaining);
            }
        }

        // 检查总计限额
        if (limitTerms.totalLimit > 0) {
            uint256 totalRemaining = limitTerms.totalLimit - state.totalSpent;
            if (amount > totalRemaining) {
                revert ExceedsTotalLimit(amount, totalRemaining);
            }
        }
    }

    /**
     * @notice 执行后更新状态
     * @dev 记录支出金额
     */
    function afterHook(
        bytes calldata terms,
        bytes calldata args,
        uint8 mode,
        bytes calldata executionCalldata,
        bytes32 delegationHash,
        address delegator,
        address redeemer
    ) external override onlyAuthorizedCaller {
        LimitTerms memory limitTerms = _decodeTerms(terms);
        uint256 amount = _extractAmount(args, executionCalldata);

        UsageState storage state = usageStates[delegationHash];

        // 更新使用状态
        state.spentToday += amount;
        state.totalSpent += amount;

        emit SpendingRecorded(
            delegationHash,
            limitTerms.token,
            amount,
            state.spentToday,
            state.totalSpent
        );
    }

    /**
     * @notice 获取元数据 URI
     */
    function getMetadataURI() external pure override returns (string memory) {
        return "https://shield-protocol.xyz/caveats/spending-limit";
    }

    // ============ 视图函数 ============

    /**
     * @notice 获取 Delegation 的使用状态
     */
    function getUsageState(bytes32 delegationHash) external view returns (UsageState memory) {
        return usageStates[delegationHash];
    }

    /**
     * @notice 获取剩余可用额度
     */
    function getRemainingAllowance(
        bytes32 delegationHash,
        bytes calldata terms
    ) external view returns (uint256 dailyRemaining, uint256 totalRemaining) {
        LimitTerms memory limitTerms = _decodeTerms(terms);
        UsageState memory state = usageStates[delegationHash];

        // 检查是否跨天
        uint256 currentDay = block.timestamp / SECONDS_PER_DAY;
        uint256 spentToday = state.lastResetDay < currentDay ? 0 : state.spentToday;

        dailyRemaining = limitTerms.dailyLimit > 0
            ? limitTerms.dailyLimit - spentToday
            : type(uint256).max;

        totalRemaining = limitTerms.totalLimit > 0
            ? limitTerms.totalLimit - state.totalSpent
            : type(uint256).max;
    }

    // ============ 内部函数 ============

    /**
     * @notice 解码 Terms
     */
    function _decodeTerms(bytes calldata terms) internal pure returns (LimitTerms memory) {
        if (terms.length < 128) revert InvalidTerms();
        return abi.decode(terms, (LimitTerms));
    }

    /**
     * @notice 从 calldata 提取金额
     * @dev args 必须包含 ABI 编码的 uint256 金额
     *
     * 编码约定:
     * - args = abi.encode(uint256 amount)
     * - 金额必须大于 0
     *
     * 安全注意:
     * - 如果 args 格式不正确，将 revert 以防止绕过限额检查
     */
    function _extractAmount(
        bytes calldata args,
        bytes calldata executionCalldata
    ) internal pure returns (uint256) {
        // 确保 args 至少包含一个 uint256 (32 字节)
        if (args.length < 32) {
            revert InvalidArgs();
        }
        return abi.decode(args, (uint256));
    }

    // ============ 辅助函数 ============

    /**
     * @notice 编码 Terms
     * @dev 便于前端构建 Caveat
     */
    function encodeTerms(
        address token,
        uint256 singleTxLimit,
        uint256 dailyLimit,
        uint256 totalLimit
    ) external pure returns (bytes memory) {
        return abi.encode(LimitTerms({
            token: token,
            singleTxLimit: singleTxLimit,
            dailyLimit: dailyLimit,
            totalLimit: totalLimit
        }));
    }
}
