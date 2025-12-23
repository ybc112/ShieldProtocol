// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ICaveatEnforcer} from "../interfaces/ICaveatEnforcer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AllowedTargetsEnforcer
 * @author Shield Protocol Team
 * @notice 目标地址白名单 Caveat 执行器
 * @dev 限制 Delegation 只能调用指定的合约地址
 *
 * 功能:
 * 1. 白名单模式: 只允许调用指定合约
 * 2. 黑名单模式: 禁止调用指定合约
 *
 * 使用场景:
 * - 限制 DCA 只能调用 Uniswap Router
 * - 限制订阅只能转账给指定创作者
 * - 防止恶意合约被调用
 *
 * Terms 编码格式:
 * - isWhitelist: bool - true 为白名单模式，false 为黑名单模式
 * - targets: address[] - 目标地址列表
 */
contract AllowedTargetsEnforcer is ICaveatEnforcer, Ownable {
    // ============ 结构体 ============

    struct TargetTerms {
        bool isWhitelist;       // true = 白名单模式, false = 黑名单模式
        address[] targets;      // 目标地址列表
    }

    // ============ 状态变量 ============

    /// @notice 授权的 DelegationManager 地址
    mapping(address => bool) public authorizedCallers;

    // ============ 事件 ============

    event AuthorizedCallerAdded(address indexed caller);
    event AuthorizedCallerRemoved(address indexed caller);

    event TargetValidated(
        bytes32 indexed delegationHash,
        address indexed target,
        bool allowed
    );

    // ============ 错误 ============

    error TargetNotAllowed(address target);
    error TargetBlacklisted(address target);
    error InvalidTerms();
    error InvalidExecutionCalldata();
    error EmptyTargetList();
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
     * @dev 检查目标地址是否在允许列表中
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
        // 解码配置
        TargetTerms memory targetTerms = _decodeTerms(terms);

        // 从 executionCalldata 提取目标地址
        address target = _extractTarget(executionCalldata);

        // 验证目标地址
        bool found = _isInList(target, targetTerms.targets);

        if (targetTerms.isWhitelist) {
            // 白名单模式: 必须在列表中
            if (!found) {
                revert TargetNotAllowed(target);
            }
        } else {
            // 黑名单模式: 不能在列表中
            if (found) {
                revert TargetBlacklisted(target);
            }
        }

        emit TargetValidated(delegationHash, target, true);
    }

    /**
     * @notice 执行后钩子 (不做任何操作)
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
        // 不需要后处理
    }

    /**
     * @notice 获取元数据 URI
     */
    function getMetadataURI() external pure override returns (string memory) {
        return "https://shield-protocol.xyz/caveats/allowed-targets";
    }

    // ============ 内部函数 ============

    /**
     * @notice 解码 Terms
     */
    function _decodeTerms(bytes calldata terms) internal pure returns (TargetTerms memory) {
        if (terms.length < 64) revert InvalidTerms();
        return abi.decode(terms, (TargetTerms));
    }

    /**
     * @notice 从 executionCalldata 提取目标地址
     * @dev 编码约定: executionCalldata 的前 20 字节必须是目标合约地址
     *
     * 这个编码约定需要与 DelegationManager 保持一致:
     * executionCalldata = abi.encodePacked(address target, bytes data)
     *
     * 常见用法:
     * - 直接调用: target = 被调用的合约地址
     * - 代币转账: target = 代币合约地址
     * - DEX 交易: target = Router 合约地址
     *
     * 安全注意:
     * - 如果 executionCalldata 格式不正确，将 revert 以防止绕过检查
     */
    function _extractTarget(bytes calldata executionCalldata) internal pure returns (address) {
        if (executionCalldata.length < 20) {
            revert InvalidExecutionCalldata();
        }
        return address(bytes20(executionCalldata[:20]));
    }

    /**
     * @notice 检查地址是否在列表中
     */
    function _isInList(address target, address[] memory list) internal pure returns (bool) {
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == target) {
                return true;
            }
        }
        return false;
    }

    // ============ 辅助函数 ============

    /**
     * @notice 编码白名单 Terms
     */
    function encodeWhitelistTerms(address[] calldata targets) external pure returns (bytes memory) {
        if (targets.length == 0) revert EmptyTargetList();
        return abi.encode(TargetTerms({
            isWhitelist: true,
            targets: targets
        }));
    }

    /**
     * @notice 编码黑名单 Terms
     */
    function encodeBlacklistTerms(address[] calldata targets) external pure returns (bytes memory) {
        if (targets.length == 0) revert EmptyTargetList();
        return abi.encode(TargetTerms({
            isWhitelist: false,
            targets: targets
        }));
    }

    /**
     * @notice 验证目标地址 (视图函数，用于前端预检)
     */
    function validateTarget(
        bytes calldata terms,
        address target
    ) external pure returns (bool allowed, string memory reason) {
        TargetTerms memory targetTerms = _decodeTerms(terms);
        bool found = _isInList(target, targetTerms.targets);

        if (targetTerms.isWhitelist) {
            if (found) {
                return (true, "Target is whitelisted");
            } else {
                return (false, "Target not in whitelist");
            }
        } else {
            if (found) {
                return (false, "Target is blacklisted");
            } else {
                return (true, "Target not in blacklist");
            }
        }
    }
}
