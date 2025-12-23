// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ShieldCore} from "../src/core/ShieldCore.sol";
import {IShieldCore} from "../src/interfaces/IShieldCore.sol";
import {MockERC20, MockSwapRouter, MockWETH} from "./mocks/Mocks.sol";

/**
 * @title ShieldCoreSecurityTest
 * @notice 测试 ShieldCore 的安全改进功能
 * 
 * 测试内容:
 * 1. 限额修改冷却期 (24小时)
 * 2. 白名单显式启用模式
 * 3. recordSpending 返回值修复
 */
contract ShieldCoreSecurityTest is Test {
    ShieldCore public shieldCore;

    address public owner;
    address public user1;
    address public executor;
    address public mockContract;

    MockERC20 public usdc;

    // 事件
    event ConfigUpdateProposed(
        address indexed user,
        uint256 newDailyLimit,
        uint256 newSingleTxLimit,
        uint256 effectiveTime
    );
    event ConfigUpdateExecuted(address indexed user);
    event ConfigUpdateCancelled(address indexed user);
    event WhitelistModeEnabled(address indexed user);
    event WhitelistModeDisabled(address indexed user);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        executor = makeAddr("executor");
        mockContract = makeAddr("mockContract");

        // 部署合约
        shieldCore = new ShieldCore();
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // 设置授权执行器
        shieldCore.addAuthorizedExecutor(executor);

        // 给 mockContract 添加代码（模拟合约）
        vm.etch(mockContract, hex"00");
    }

    // ==================== 限额修改冷却期测试 ====================

    function test_ProposeConfigUpdate_Success() public {
        // 激活 Shield
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        // 提议更新
        vm.prank(user1);
        vm.expectEmit(true, false, false, false);
        emit ConfigUpdateProposed(user1, 2000e6, 200e6, block.timestamp + 24 hours);
        shieldCore.proposeShieldConfigUpdate(2000e6, 200e6);

        // 检查待生效的更新
        (
            uint256 newDailyLimit,
            uint256 newSingleTxLimit,
            uint256 effectiveTime,
            bool pending
        ) = shieldCore.pendingConfigUpdates(user1);

        assertEq(newDailyLimit, 2000e6, "New daily limit should match");
        assertEq(newSingleTxLimit, 200e6, "New single tx limit should match");
        assertEq(effectiveTime, block.timestamp + 24 hours, "Effective time should be 24h later");
        assertTrue(pending, "Should be pending");
    }

    function test_ExecuteConfigUpdate_Success() public {
        // 激活并提议更新
        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);
        shieldCore.proposeShieldConfigUpdate(2000e6, 200e6);
        vm.stopPrank();

        // 快进 24 小时
        vm.warp(block.timestamp + 24 hours);

        // 执行更新
        vm.prank(user1);
        vm.expectEmit(true, false, false, false);
        emit ConfigUpdateExecuted(user1);
        shieldCore.executeShieldConfigUpdate();

        // 验证配置已更新
        IShieldCore.ShieldConfig memory config = shieldCore.getShieldConfig(user1);
        assertEq(config.dailySpendLimit, 2000e6, "Daily limit should be updated");
        assertEq(config.singleTxLimit, 200e6, "Single tx limit should be updated");

        // 验证待生效记录已删除
        (, , , bool pending) = shieldCore.pendingConfigUpdates(user1);
        assertFalse(pending, "Should no longer be pending");
    }

    function test_RevertWhen_ExecuteConfigUpdateTooEarly() public {
        // 激活并提议更新
        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);
        shieldCore.proposeShieldConfigUpdate(2000e6, 200e6);

        // 尝试立即执行（不等待冷却期）
        vm.expectRevert("Cooldown not expired");
        shieldCore.executeShieldConfigUpdate();
        vm.stopPrank();
    }

    function test_RevertWhen_ExecuteConfigUpdateWithoutProposal() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.prank(user1);
        vm.expectRevert("No pending update");
        shieldCore.executeShieldConfigUpdate();
    }

    function test_CancelConfigUpdate_Success() public {
        // 激活并提议更新
        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);
        shieldCore.proposeShieldConfigUpdate(2000e6, 200e6);

        // 取消更新
        vm.expectEmit(true, false, false, false);
        emit ConfigUpdateCancelled(user1);
        shieldCore.cancelShieldConfigUpdate();
        vm.stopPrank();

        // 验证待生效记录已删除
        (, , , bool pending) = shieldCore.pendingConfigUpdates(user1);
        assertFalse(pending, "Should no longer be pending");
    }

    function test_ConfigUpdateCooldownPreventsAbuse() public {
        // 模拟攻击场景：用户试图快速修改限额来绕过保护

        // 1. 激活 Shield，设置较低限额
        vm.prank(user1);
        shieldCore.activateShield(100e6, 50e6);

        // 2. 提议大幅提高限额
        vm.prank(user1);
        shieldCore.proposeShieldConfigUpdate(10000e6, 5000e6);

        // 3. 试图立即记录大额支出（应该仍然受原限额约束）
        vm.prank(executor);
        vm.expectRevert(); // 应该因为超出原限额而失败
        shieldCore.recordSpending(user1, address(usdc), 1000e6);

        // 4. 即使等待 24 小时执行更新，之前的交易已被阻止
        vm.warp(block.timestamp + 24 hours);
        vm.prank(user1);
        shieldCore.executeShieldConfigUpdate();

        // 现在才能使用新限额
        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), 1000e6);
    }

    // ==================== 白名单模式测试 ====================

    function test_WhitelistMode_DefaultDisabled() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        // 默认情况下，白名单模式未启用
        IShieldCore.ShieldConfig memory config = shieldCore.getShieldConfig(user1);
        assertFalse(config.whitelistEnabled, "Whitelist mode should be disabled by default");

        // 未启用白名单模式时，任何合约都可以访问
        bool allowed = shieldCore.isWhitelisted(user1, mockContract);
        assertTrue(allowed, "Should allow all contracts when whitelist disabled");
    }

    function test_WhitelistMode_EnableAndEnforce() public {
        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        // 启用白名单模式
        vm.expectEmit(true, false, false, false);
        emit WhitelistModeEnabled(user1);
        shieldCore.enableWhitelistMode();
        vm.stopPrank();

        // 启用后，未在白名单中的合约应该被拒绝
        bool allowed = shieldCore.isWhitelisted(user1, mockContract);
        assertFalse(allowed, "Should reject non-whitelisted contracts");
    }

    function test_WhitelistMode_AddContractAndCheck() public {
        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);
        shieldCore.enableWhitelistMode();

        // 添加合约到白名单
        shieldCore.addWhitelistedContract(mockContract);
        vm.stopPrank();

        // 现在应该允许访问
        bool allowed = shieldCore.isWhitelisted(user1, mockContract);
        assertTrue(allowed, "Should allow whitelisted contract");
    }

    function test_WhitelistMode_DisableAllowsAll() public {
        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);
        shieldCore.enableWhitelistMode();
        shieldCore.addWhitelistedContract(mockContract);

        // 禁用白名单模式
        vm.expectEmit(true, false, false, false);
        emit WhitelistModeDisabled(user1);
        shieldCore.disableWhitelistMode();
        vm.stopPrank();

        // 禁用后，所有合约都应该被允许
        address otherContract = makeAddr("otherContract");
        vm.etch(otherContract, hex"00");
        bool allowed = shieldCore.isWhitelisted(user1, otherContract);
        assertTrue(allowed, "Should allow all contracts when whitelist disabled");
    }

    // ==================== RecordSpending 返回值测试 ====================

    function test_RecordSpending_NoReturnValueOnRevert() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        // 记录超出限额的支出应该直接 revert
        vm.prank(executor);
        vm.expectRevert();
        shieldCore.recordSpending(user1, address(usdc), 2000e6);
    }

    function test_RecordSpending_NoFalseReturns() public {
        // 这个测试确认 recordSpending 永远不会返回 false
        // 它要么成功（无返回值），要么 revert

        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        // 成功的情况
        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), 50e6);

        // 失败的情况会直接 revert，不会有返回值
        vm.prank(executor);
        try shieldCore.recordSpending(user1, address(usdc), 2000e6) {
            fail("Should have reverted");
        } catch {
            // Expected to revert
        }
    }

    // ==================== 集成安全测试 ====================

    function test_SecurityStack_CooldownAndWhitelist() public {
        // 测试多层安全机制同时工作

        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);
        shieldCore.enableWhitelistMode();
        shieldCore.addWhitelistedContract(mockContract);
        vm.stopPrank();

        // 提议提高限额
        vm.prank(user1);
        shieldCore.proposeShieldConfigUpdate(5000e6, 500e6);

        // 在冷却期内，即使是白名单合约，也受限于原限额
        vm.prank(executor);
        vm.expectRevert();
        shieldCore.recordSpending(user1, address(usdc), 200e6);

        // 等待冷却期
        vm.warp(block.timestamp + 24 hours);
        vm.prank(user1);
        shieldCore.executeShieldConfigUpdate();

        // 现在可以使用新限额了
        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), 200e6);
    }

    function test_EmergencyMode_OverridesAll() public {
        // 即使配置更新等待中，紧急模式也能立即阻止所有操作

        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);
        shieldCore.proposeShieldConfigUpdate(2000e6, 200e6);
        
        // 启用紧急模式
        shieldCore.enableEmergencyMode();
        vm.stopPrank();

        // 任何支出都应该被拒绝
        vm.prank(executor);
        vm.expectRevert(IShieldCore.EmergencyModeActive.selector);
        shieldCore.recordSpending(user1, address(usdc), 10e6);
    }

    // ==================== 边界条件测试 ====================

    function test_ProposeUpdate_ValidatesLimits() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        // 日限额太小
        vm.prank(user1);
        vm.expectRevert(IShieldCore.InvalidLimit.selector);
        shieldCore.proposeShieldConfigUpdate(100, 50);

        // 单笔限额 > 日限额
        vm.prank(user1);
        vm.expectRevert(IShieldCore.InvalidLimit.selector);
        shieldCore.proposeShieldConfigUpdate(1000e6, 2000e6);

        // 单笔限额为 0
        vm.prank(user1);
        vm.expectRevert(IShieldCore.InvalidLimit.selector);
        shieldCore.proposeShieldConfigUpdate(1000e6, 0);
    }

    function test_MultiplePendingUpdates_OnlyLastCounts() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        // 第一次提议
        vm.prank(user1);
        shieldCore.proposeShieldConfigUpdate(2000e6, 200e6);

        // 第二次提议（覆盖第一次）
        vm.prank(user1);
        shieldCore.proposeShieldConfigUpdate(3000e6, 300e6);

        // 等待冷却期
        vm.warp(block.timestamp + 24 hours);

        // 执行更新，应该是第二次提议的值
        vm.prank(user1);
        shieldCore.executeShieldConfigUpdate();

        IShieldCore.ShieldConfig memory config = shieldCore.getShieldConfig(user1);
        assertEq(config.dailySpendLimit, 3000e6, "Should use latest proposal");
        assertEq(config.singleTxLimit, 300e6, "Should use latest proposal");
    }
}




