// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ICaveatEnforcer
 * @notice Caveat 执行器接口 (兼容 MetaMask Delegation Framework)
 * @dev 定义了权限限制条件的验证接口
 *
 * Caveat 是 Delegation Framework 中的核心概念:
 * - 每个 Caveat 定义一个限制条件
 * - 在执行 Delegation 时，所有 Caveat 都必须通过验证
 * - Caveat 可以组合使用，形成复杂的权限规则
 */
interface ICaveatEnforcer {
    /**
     * @notice 在 Delegation 执行前验证
     * @param terms Caveat 的参数 (编码后的数据)
     * @param args 执行时的附加参数
     * @param mode Delegation 执行模式
     * @param executionCalldata 要执行的 calldata
     * @param delegationHash Delegation 的哈希
     * @param delegator 委托者地址
     * @param redeemer 执行者地址
     */
    function beforeHook(
        bytes calldata terms,
        bytes calldata args,
        uint8 mode,
        bytes calldata executionCalldata,
        bytes32 delegationHash,
        address delegator,
        address redeemer
    ) external;

    /**
     * @notice 在 Delegation 执行后验证
     * @param terms Caveat 的参数
     * @param args 执行时的附加参数
     * @param mode Delegation 执行模式
     * @param executionCalldata 执行的 calldata
     * @param delegationHash Delegation 的哈希
     * @param delegator 委托者地址
     * @param redeemer 执行者地址
     */
    function afterHook(
        bytes calldata terms,
        bytes calldata args,
        uint8 mode,
        bytes calldata executionCalldata,
        bytes32 delegationHash,
        address delegator,
        address redeemer
    ) external;

    /**
     * @notice 获取 Caveat 的元数据 URI
     * @return uri 元数据 URI
     */
    function getMetadataURI() external view returns (string memory uri);
}
