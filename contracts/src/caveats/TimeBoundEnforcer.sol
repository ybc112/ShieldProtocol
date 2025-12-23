// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICaveatEnforcer} from "../interfaces/ICaveatEnforcer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TimeBoundEnforcer
 * @author Shield Protocol Team
 * @notice 时间限制 Caveat 执行器
 * @dev 限制 Delegation 的有效时间范围
 *
 * 功能:
 * 1. 开始时间: 在此时间之前不可执行
 * 2. 结束时间: 在此时间之后不可执行
 * 3. 可选的执行次数限制
 *
 * 使用场景:
 * - DCA 策略的有效期限制
 * - 临时授权 (如 7 天有效)
 * - 试用期权限
 *
 * Terms 编码格式:
 * - notBefore: uint256 - 开始时间戳 (0 = 无限制)
 * - notAfter: uint256 - 结束时间戳 (0 = 无限制)
 * - maxExecutions: uint256 - 最大执行次数 (0 = 无限制)
 */
contract TimeBoundEnforcer is ICaveatEnforcer, Ownable {
    // ============ 结构体 ============

    struct TimeTerms {
        uint256 notBefore;      // 开始时间
        uint256 notAfter;       // 结束时间
        uint256 maxExecutions;  // 最大执行次数
    }

    // ============ 状态变量 ============

    /// @notice 授权的 DelegationManager 地址
    mapping(address => bool) public authorizedCallers;

    /// @notice delegationHash => 执行计数
    mapping(bytes32 => uint256) public executionCounts;

    // ============ 事件 ============

    event AuthorizedCallerAdded(address indexed caller);
    event AuthorizedCallerRemoved(address indexed caller);

    event ExecutionRecorded(
        bytes32 indexed delegationHash,
        uint256 executionNumber,
        uint256 timestamp
    );

    event DelegationExpired(bytes32 indexed delegationHash, string reason);

    // ============ 错误 ============

    error TooEarly(uint256 notBefore, uint256 currentTime);
    error TooLate(uint256 notAfter, uint256 currentTime);
    error MaxExecutionsReached(uint256 maxExecutions, uint256 currentCount);
    error InvalidTerms();
    error InvalidTimeRange();
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
     * @dev 检查当前时间是否在有效范围内
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
        TimeTerms memory timeTerms = _decodeTerms(terms);

        // 检查开始时间
        if (timeTerms.notBefore > 0 && block.timestamp < timeTerms.notBefore) {
            revert TooEarly(timeTerms.notBefore, block.timestamp);
        }

        // 检查结束时间
        if (timeTerms.notAfter > 0 && block.timestamp > timeTerms.notAfter) {
            emit DelegationExpired(delegationHash, "Time limit exceeded");
            revert TooLate(timeTerms.notAfter, block.timestamp);
        }

        // 检查执行次数
        if (timeTerms.maxExecutions > 0) {
            uint256 currentCount = executionCounts[delegationHash];
            if (currentCount >= timeTerms.maxExecutions) {
                emit DelegationExpired(delegationHash, "Max executions reached");
                revert MaxExecutionsReached(timeTerms.maxExecutions, currentCount);
            }
        }
    }

    /**
     * @notice 执行后更新计数
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
        TimeTerms memory timeTerms = _decodeTerms(terms);

        // 更新执行计数
        if (timeTerms.maxExecutions > 0) {
            executionCounts[delegationHash]++;
            emit ExecutionRecorded(
                delegationHash,
                executionCounts[delegationHash],
                block.timestamp
            );
        }
    }

    /**
     * @notice 获取元数据 URI
     */
    function getMetadataURI() external pure override returns (string memory) {
        return "https://shield-protocol.xyz/caveats/time-bound";
    }

    // ============ 视图函数 ============

    /**
     * @notice 获取 Delegation 的执行计数
     */
    function getExecutionCount(bytes32 delegationHash) external view returns (uint256) {
        return executionCounts[delegationHash];
    }

    /**
     * @notice 检查 Delegation 是否仍然有效
     */
    function isStillValid(
        bytes32 delegationHash,
        bytes calldata terms
    ) external view returns (bool valid, string memory reason) {
        TimeTerms memory timeTerms = _decodeTerms(terms);

        // 检查时间
        if (timeTerms.notBefore > 0 && block.timestamp < timeTerms.notBefore) {
            return (false, "Not started yet");
        }

        if (timeTerms.notAfter > 0 && block.timestamp > timeTerms.notAfter) {
            return (false, "Expired");
        }

        // 检查执行次数
        if (timeTerms.maxExecutions > 0) {
            if (executionCounts[delegationHash] >= timeTerms.maxExecutions) {
                return (false, "Max executions reached");
            }
        }

        return (true, "Valid");
    }

    /**
     * @notice 获取剩余有效时间
     */
    function getRemainingTime(bytes calldata terms) external view returns (uint256) {
        TimeTerms memory timeTerms = _decodeTerms(terms);

        if (timeTerms.notAfter == 0) {
            return type(uint256).max; // 无限制
        }

        if (block.timestamp >= timeTerms.notAfter) {
            return 0; // 已过期
        }

        return timeTerms.notAfter - block.timestamp;
    }

    /**
     * @notice 获取剩余执行次数
     */
    function getRemainingExecutions(
        bytes32 delegationHash,
        bytes calldata terms
    ) external view returns (uint256) {
        TimeTerms memory timeTerms = _decodeTerms(terms);

        if (timeTerms.maxExecutions == 0) {
            return type(uint256).max; // 无限制
        }

        uint256 used = executionCounts[delegationHash];
        if (used >= timeTerms.maxExecutions) {
            return 0;
        }

        return timeTerms.maxExecutions - used;
    }

    // ============ 内部函数 ============

    /**
     * @notice 解码 Terms
     */
    function _decodeTerms(bytes calldata terms) internal pure returns (TimeTerms memory) {
        if (terms.length < 96) revert InvalidTerms();
        return abi.decode(terms, (TimeTerms));
    }

    // ============ 辅助函数 ============

    /**
     * @notice 编码 Terms
     * @param notBefore 开始时间 (0 = 立即生效)
     * @param notAfter 结束时间 (0 = 永不过期)
     * @param maxExecutions 最大执行次数 (0 = 无限制)
     */
    function encodeTerms(
        uint256 notBefore,
        uint256 notAfter,
        uint256 maxExecutions
    ) external pure returns (bytes memory) {
        if (notAfter > 0 && notBefore > 0 && notBefore >= notAfter) {
            revert InvalidTimeRange();
        }

        return abi.encode(TimeTerms({
            notBefore: notBefore,
            notAfter: notAfter,
            maxExecutions: maxExecutions
        }));
    }

    /**
     * @notice 快速创建有效期 Terms
     * @param durationSeconds 有效期长度 (秒)
     * @param maxExecutions 最大执行次数
     */
    function encodeWithDuration(
        uint256 durationSeconds,
        uint256 maxExecutions
    ) external view returns (bytes memory) {
        return abi.encode(TimeTerms({
            notBefore: block.timestamp,
            notAfter: block.timestamp + durationSeconds,
            maxExecutions: maxExecutions
        }));
    }
}
