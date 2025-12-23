// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ShieldCore} from "../src/core/ShieldCore.sol";
import {DCAExecutor} from "../src/strategies/DCAExecutor.sol";
import {IDCAExecutor} from "../src/interfaces/IDCAExecutor.sol";
import {IShieldCore} from "../src/interfaces/IShieldCore.sol";
import {MockERC20, MockSwapRouter, MockWETH} from "./mocks/Mocks.sol";

/**
 * @title ShieldCoreTest
 * @notice ShieldCore 合约完整测试套件
 */
contract ShieldCoreTest is Test {
    ShieldCore public shieldCore;

    address public owner;
    address public user1;
    address public user2;
    address public executor;

    MockERC20 public usdc;
    MockWETH public weth;

    // 事件定义
    event ShieldActivated(address indexed user, uint256 dailyLimit, uint256 singleTxLimit, uint256 timestamp);
    event ShieldConfigUpdated(address indexed user, uint256 newDailyLimit, uint256 newSingleTxLimit);
    event ShieldDeactivated(address indexed user, uint256 timestamp);
    event EmergencyModeEnabled(address indexed user, uint256 timestamp);
    event EmergencyModeDisabled(address indexed user, uint256 timestamp);
    event SpendingRecorded(address indexed user, address indexed token, uint256 amount, uint256 dailyTotal, uint256 timestamp);
    event DailyLimitReset(address indexed user, uint256 timestamp);
    event ContractWhitelisted(address indexed user, address indexed contractAddress);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        executor = makeAddr("executor");

        // 部署合约
        shieldCore = new ShieldCore();

        // 部署 Mock 代币
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockWETH();

        // 设置授权执行器
        shieldCore.addAuthorizedExecutor(executor);
    }

    // ==================== 激活测试 ====================

    function test_ActivateShield() public {
        uint256 dailyLimit = 1000e6; // 1000 USDC
        uint256 singleTxLimit = 100e6; // 100 USDC

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit ShieldActivated(user1, dailyLimit, singleTxLimit, block.timestamp);
        shieldCore.activateShield(dailyLimit, singleTxLimit);

        // 验证配置
        IShieldCore.ShieldConfig memory config = shieldCore.getShieldConfig(user1);
        assertEq(config.dailySpendLimit, dailyLimit, "Daily limit mismatch");
        assertEq(config.singleTxLimit, singleTxLimit, "Single tx limit mismatch");
        assertTrue(config.isActive, "Shield should be active");
        assertFalse(config.emergencyMode, "Emergency mode should be off");
        assertEq(config.spentToday, 0, "Spent today should be 0");
    }

    function test_ActivateShield_MultiplUsers() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.prank(user2);
        shieldCore.activateShield(2000e6, 200e6);

        IShieldCore.ShieldConfig memory config1 = shieldCore.getShieldConfig(user1);
        IShieldCore.ShieldConfig memory config2 = shieldCore.getShieldConfig(user2);

        assertEq(config1.dailySpendLimit, 1000e6);
        assertEq(config2.dailySpendLimit, 2000e6);
    }

    function test_RevertWhen_ActivateWithDailyLimitTooSmall() public {
        vm.prank(user1);
        vm.expectRevert(IShieldCore.InvalidLimit.selector);
        shieldCore.activateShield(100, 50); // 小于 MIN_DAILY_LIMIT (1e6)
    }

    function test_RevertWhen_ActivateWithSingleTxLimitExceedsDaily() public {
        vm.prank(user1);
        vm.expectRevert(IShieldCore.InvalidLimit.selector);
        shieldCore.activateShield(1000e6, 2000e6); // 单笔 > 每日
    }

    function test_RevertWhen_ActivateWithZeroSingleTxLimit() public {
        vm.prank(user1);
        vm.expectRevert(IShieldCore.InvalidLimit.selector);
        shieldCore.activateShield(1000e6, 0);
    }

    function test_RevertWhen_AlreadyActivated() public {
        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.expectRevert(IShieldCore.ShieldAlreadyActive.selector);
        shieldCore.activateShield(2000e6, 200e6);
        vm.stopPrank();
    }

    // ==================== 支出记录测试 ====================

    function test_RecordSpending_Success() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.prank(executor);
        vm.expectEmit(true, true, false, true);
        emit SpendingRecorded(user1, address(usdc), 50e6, 50e6, block.timestamp);
        shieldCore.recordSpending(user1, address(usdc), 50e6);

        uint256 remaining = shieldCore.getRemainingDailyAllowance(user1, address(usdc));
        assertEq(remaining, 950e6, "Remaining should be 950 USDC");
    }

    function test_RecordSpending_MultipleTransactions() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.startPrank(executor);
        shieldCore.recordSpending(user1, address(usdc), 100e6);
        shieldCore.recordSpending(user1, address(usdc), 50e6);
        shieldCore.recordSpending(user1, address(usdc), 30e6);
        vm.stopPrank();

        uint256 remaining = shieldCore.getRemainingDailyAllowance(user1, address(usdc));
        assertEq(remaining, 820e6, "Remaining should be 820 USDC");
    }

    function test_RecordSpending_ResetOnNewDay() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        // 第一天支出
        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), 100e6);

        uint256 remainingDay1 = shieldCore.getRemainingDailyAllowance(user1, address(usdc));
        assertEq(remainingDay1, 900e6);

        // 快进一天
        vm.warp(block.timestamp + 1 days);

        // 验证已重置
        uint256 remainingDay2 = shieldCore.getRemainingDailyAllowance(user1, address(usdc));
        assertEq(remainingDay2, 1000e6, "Should reset to full daily limit");

        // 新的一天可以再次支出
        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), 100e6);
    }

    function test_RevertWhen_ExceedsDailyLimit() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 500e6);

        vm.startPrank(executor);
        shieldCore.recordSpending(user1, address(usdc), 500e6);
        shieldCore.recordSpending(user1, address(usdc), 400e6);

        // 第三次支出超过剩余限额
        vm.expectRevert(abi.encodeWithSelector(
            IShieldCore.ExceedsDailyLimit.selector,
            200e6, // requested
            100e6  // remaining
        ));
        shieldCore.recordSpending(user1, address(usdc), 200e6);
        vm.stopPrank();
    }

    function test_RevertWhen_ExceedsSingleTxLimit() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(
            IShieldCore.ExceedsSingleTxLimit.selector,
            200e6, // requested
            100e6  // limit
        ));
        shieldCore.recordSpending(user1, address(usdc), 200e6);
    }

    function test_RevertWhen_NotAuthorizedExecutor() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.prank(user2); // 非授权执行器
        vm.expectRevert("Not authorized executor");
        shieldCore.recordSpending(user1, address(usdc), 50e6);
    }

    function test_RevertWhen_ShieldNotActive() public {
        vm.prank(executor);
        vm.expectRevert(IShieldCore.ShieldNotActive.selector);
        shieldCore.recordSpending(user1, address(usdc), 50e6);
    }

    // ==================== 紧急模式测试 ====================

    function test_EnableEmergencyMode() public {
        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.expectEmit(true, false, false, true);
        emit EmergencyModeEnabled(user1, block.timestamp);
        shieldCore.enableEmergencyMode();

        IShieldCore.ShieldConfig memory config = shieldCore.getShieldConfig(user1);
        assertTrue(config.emergencyMode, "Emergency mode should be enabled");
        vm.stopPrank();
    }

    function test_RevertWhen_SpendingInEmergencyMode() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.prank(user1);
        shieldCore.enableEmergencyMode();

        vm.prank(executor);
        vm.expectRevert(IShieldCore.EmergencyModeActive.selector);
        shieldCore.recordSpending(user1, address(usdc), 50e6);
    }

    function test_DisableEmergencyMode() public {
        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);
        shieldCore.enableEmergencyMode();

        vm.expectEmit(true, false, false, true);
        emit EmergencyModeDisabled(user1, block.timestamp);
        shieldCore.disableEmergencyMode();

        IShieldCore.ShieldConfig memory config = shieldCore.getShieldConfig(user1);
        assertFalse(config.emergencyMode);
        vm.stopPrank();

        // 验证可以再次支出
        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), 50e6);
    }

    // ==================== 配置更新测试 ====================

    function test_UpdateShieldConfig() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        // 两阶段配置更新
        vm.startPrank(user1);
        shieldCore.proposeShieldConfigUpdate(2000e6, 200e6);

        // 等待 24 小时冷却期
        vm.warp(block.timestamp + 24 hours);

        vm.expectEmit(true, false, false, true);
        emit ShieldConfigUpdated(user1, 2000e6, 200e6);
        shieldCore.executeShieldConfigUpdate();
        vm.stopPrank();

        IShieldCore.ShieldConfig memory config = shieldCore.getShieldConfig(user1);
        assertEq(config.dailySpendLimit, 2000e6);
        assertEq(config.singleTxLimit, 200e6);
    }

    function test_DeactivateShield() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit ShieldDeactivated(user1, block.timestamp);
        shieldCore.deactivateShield();

        IShieldCore.ShieldConfig memory config = shieldCore.getShieldConfig(user1);
        assertFalse(config.isActive);
    }

    function test_RevertWhen_DeactivateNotActive() public {
        vm.prank(user1);
        vm.expectRevert(IShieldCore.ShieldNotActive.selector);
        shieldCore.deactivateShield();
    }

    // ==================== 白名单测试 ====================

    function test_AddWhitelistedContract() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit ContractWhitelisted(user1, address(usdc));
        shieldCore.addWhitelistedContract(address(usdc));

        assertTrue(shieldCore.isWhitelisted(user1, address(usdc)));
    }

    function test_WhitelistDefaultAllowAll() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        // 没有设置白名单，默认允许所有
        assertTrue(shieldCore.isWhitelisted(user1, address(0x123)));
    }

    function test_WhitelistOnlyAllowListed() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.startPrank(user1);
        shieldCore.addWhitelistedContract(address(usdc));
        // 必须启用白名单模式才能生效
        shieldCore.enableWhitelistMode();
        vm.stopPrank();

        assertTrue(shieldCore.isWhitelisted(user1, address(usdc)));
        assertFalse(shieldCore.isWhitelisted(user1, address(weth)));
    }

    function test_RemoveWhitelistedContract() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.startPrank(user1);
        shieldCore.addWhitelistedContract(address(usdc));
        shieldCore.addWhitelistedContract(address(weth));
        // 启用白名单模式
        shieldCore.enableWhitelistMode();

        shieldCore.removeWhitelistedContract(address(usdc));
        vm.stopPrank();

        assertFalse(shieldCore.isWhitelisted(user1, address(usdc)));
        assertTrue(shieldCore.isWhitelisted(user1, address(weth)));
    }

    function test_GetWhitelistedContracts() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.startPrank(user1);
        shieldCore.addWhitelistedContract(address(usdc));
        shieldCore.addWhitelistedContract(address(weth));
        vm.stopPrank();

        address[] memory whitelist = shieldCore.getWhitelistedContracts(user1);
        assertEq(whitelist.length, 2);
    }

    // ==================== 检查支出允许测试 ====================

    function test_CheckSpendingAllowed_Success() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        (bool allowed, string memory reason) = shieldCore.checkSpendingAllowed(user1, address(usdc), 50e6);
        assertTrue(allowed);
        assertEq(reason, "");
    }

    function test_CheckSpendingAllowed_ShieldNotActive() public {
        (bool allowed, string memory reason) = shieldCore.checkSpendingAllowed(user1, address(usdc), 50e6);
        assertFalse(allowed);
        assertEq(reason, "Shield not active");
    }

    function test_CheckSpendingAllowed_EmergencyMode() public {
        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);
        shieldCore.enableEmergencyMode();
        vm.stopPrank();

        (bool allowed, string memory reason) = shieldCore.checkSpendingAllowed(user1, address(usdc), 50e6);
        assertFalse(allowed);
        assertEq(reason, "Emergency mode enabled");
    }

    function test_CheckSpendingAllowed_ExceedsSingleTx() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        (bool allowed, string memory reason) = shieldCore.checkSpendingAllowed(user1, address(usdc), 200e6);
        assertFalse(allowed);
        assertEq(reason, "Exceeds single transaction limit");
    }

    function test_CheckSpendingAllowed_ExceedsDaily() public {
        vm.prank(user1);
        shieldCore.activateShield(200e6, 100e6); // 每日200e6, 单笔100e6

        // 先支出一些
        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), 100e6);
        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), 50e6);

        // 已支出 150e6, 剩余 50e6
        (bool allowed, string memory reason) = shieldCore.checkSpendingAllowed(user1, address(usdc), 50e6);
        assertTrue(allowed); // 50e6 <= 50e6

        // 尝试支出 60e6 - 不超过单笔限额 (100e6) 但超过剩余每日额度 (50e6)
        (allowed, reason) = shieldCore.checkSpendingAllowed(user1, address(usdc), 60e6);
        assertFalse(allowed);
        assertEq(reason, "Exceeds daily limit");
    }

    // ==================== 代币限额测试 ====================

    function test_SetTokenLimit() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.prank(user1);
        shieldCore.setTokenLimit(address(usdc), 500e6);

        IShieldCore.TokenLimit memory limit = shieldCore.getTokenLimit(user1, address(usdc));
        assertEq(limit.dailyLimit, 500e6);
        assertEq(limit.token, address(usdc));
    }

    function test_RemoveTokenLimit() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.startPrank(user1);
        shieldCore.setTokenLimit(address(usdc), 500e6);
        shieldCore.removeTokenLimit(address(usdc));
        vm.stopPrank();

        IShieldCore.TokenLimit memory limit = shieldCore.getTokenLimit(user1, address(usdc));
        assertEq(limit.dailyLimit, 0);
    }

    // ==================== 管理函数测试 ====================

    function test_AddAuthorizedExecutor() public {
        address newExecutor = makeAddr("newExecutor");

        shieldCore.addAuthorizedExecutor(newExecutor);
        assertTrue(shieldCore.authorizedExecutors(newExecutor));
    }

    function test_RemoveAuthorizedExecutor() public {
        shieldCore.removeAuthorizedExecutor(executor);
        assertFalse(shieldCore.authorizedExecutors(executor));
    }

    function test_SetProtocolPaused() public {
        shieldCore.setProtocolPaused(true);
        assertTrue(shieldCore.protocolPaused());

        // 暂停后无法激活 Shield
        vm.prank(user1);
        vm.expectRevert("Protocol paused");
        shieldCore.activateShield(1000e6, 100e6);
    }

    function test_RevertWhen_NonOwnerCallsAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        shieldCore.addAuthorizedExecutor(user2);
    }

    // ==================== Fuzz 测试 ====================

    function testFuzz_ActivateShield(uint256 dailyLimit, uint256 singleTxLimit) public {
        // 约束参数范围
        dailyLimit = bound(dailyLimit, 1e6, 1e30);
        singleTxLimit = bound(singleTxLimit, 1, dailyLimit);

        vm.prank(user1);
        shieldCore.activateShield(dailyLimit, singleTxLimit);

        IShieldCore.ShieldConfig memory config = shieldCore.getShieldConfig(user1);
        assertEq(config.dailySpendLimit, dailyLimit);
        assertEq(config.singleTxLimit, singleTxLimit);
    }

    function testFuzz_RecordSpending(uint256 amount) public {
        uint256 dailyLimit = 1000e6;
        uint256 singleTxLimit = 100e6;

        vm.prank(user1);
        shieldCore.activateShield(dailyLimit, singleTxLimit);

        // 约束金额在单笔限额内
        amount = bound(amount, 1, singleTxLimit);

        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), amount);

        uint256 remaining = shieldCore.getRemainingDailyAllowance(user1, address(usdc));
        assertEq(remaining, dailyLimit - amount);
    }

    // ==================== 边界情况测试 ====================

    function test_SpendExactDailyLimit() public {
        vm.prank(user1);
        shieldCore.activateShield(100e6, 100e6); // daily = single = 100 USDC

        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), 100e6);

        uint256 remaining = shieldCore.getRemainingDailyAllowance(user1, address(usdc));
        assertEq(remaining, 0);

        // 再次支出应该失败
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(
            IShieldCore.ExceedsDailyLimit.selector,
            1,
            0
        ));
        shieldCore.recordSpending(user1, address(usdc), 1);
    }

    function test_SpendExactSingleTxLimit() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), 100e6);
    }

    function test_DayBoundary() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        // 在一天结束前支出
        vm.warp(86400 - 1); // 23:59:59
        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), 100e6);

        uint256 remaining1 = shieldCore.getRemainingDailyAllowance(user1, address(usdc));
        assertEq(remaining1, 900e6);

        // 跨过午夜
        vm.warp(86400); // 00:00:00 next day
        uint256 remaining2 = shieldCore.getRemainingDailyAllowance(user1, address(usdc));
        assertEq(remaining2, 1000e6, "Should reset at midnight");
    }

    // ==================== 补充测试 ====================

    function test_TokenLimit_EnforceOnRecordSpending() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        // 设置代币特定限额 (比全局限额低)
        vm.prank(user1);
        shieldCore.setTokenLimit(address(usdc), 150e6);

        // 第一次支出 100e6
        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), 100e6);

        // 检查剩余额度应该是 50e6 (代币限额更严格)
        uint256 remaining = shieldCore.getRemainingDailyAllowance(user1, address(usdc));
        assertEq(remaining, 50e6, "Should use token-specific limit");
    }

    function test_TokenLimit_DailyReset() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.prank(user1);
        shieldCore.setTokenLimit(address(usdc), 200e6);

        // 第一天支出
        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), 100e6);

        IShieldCore.TokenLimit memory limit1 = shieldCore.getTokenLimit(user1, address(usdc));
        assertEq(limit1.spentToday, 100e6);

        // 快进一天
        vm.warp(block.timestamp + 1 days);

        // 支出后代币限额应该重置
        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), 50e6);

        uint256 remaining = shieldCore.getRemainingDailyAllowance(user1, address(usdc));
        assertEq(remaining, 150e6); // 200 - 50 = 150
    }

    function test_ReActivate_AfterDeactivate() public {
        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);
        shieldCore.deactivateShield();

        // 重新激活
        shieldCore.activateShield(2000e6, 200e6);
        vm.stopPrank();

        IShieldCore.ShieldConfig memory config = shieldCore.getShieldConfig(user1);
        assertTrue(config.isActive);
        assertEq(config.dailySpendLimit, 2000e6);
        assertEq(config.singleTxLimit, 200e6);
    }

    function test_MultipleExecutors() public {
        address executor2 = makeAddr("executor2");
        shieldCore.addAuthorizedExecutor(executor2);

        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        // 两个执行器都可以记录支出
        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), 50e6);

        vm.prank(executor2);
        shieldCore.recordSpending(user1, address(usdc), 50e6);

        uint256 remaining = shieldCore.getRemainingDailyAllowance(user1, address(usdc));
        assertEq(remaining, 900e6);
    }

    function test_ProtocolPausedEvent() public {
        shieldCore.setProtocolPaused(true);
        assertTrue(shieldCore.protocolPaused());

        shieldCore.setProtocolPaused(false);
        assertFalse(shieldCore.protocolPaused());
    }

    function test_EmergencyMode_BlocksUpdate() public {
        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);
        shieldCore.enableEmergencyMode();

        // 紧急模式下应该无法提议更新配置
        vm.expectRevert(IShieldCore.EmergencyModeActive.selector);
        shieldCore.proposeShieldConfigUpdate(2000e6, 200e6);
        vm.stopPrank();
    }

    function test_CheckSpendingAllowed_AfterDailyReset() public {
        vm.prank(user1);
        shieldCore.activateShield(100e6, 100e6);

        // 用完所有限额
        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), 100e6);

        (bool allowed1, ) = shieldCore.checkSpendingAllowed(user1, address(usdc), 50e6);
        assertFalse(allowed1);

        // 快进一天
        vm.warp(block.timestamp + 1 days);

        (bool allowed2, string memory reason) = shieldCore.checkSpendingAllowed(user1, address(usdc), 50e6);
        assertTrue(allowed2);
        assertEq(reason, "");
    }

    function testFuzz_DayBoundary(uint256 timeOffset) public {
        timeOffset = bound(timeOffset, 0, 365 days);

        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.warp(block.timestamp + timeOffset);

        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), 100e6);

        uint256 remaining = shieldCore.getRemainingDailyAllowance(user1, address(usdc));
        assertEq(remaining, 900e6);
    }

    // ==================== 补充覆盖测试 ====================

    function test_Unpause() public {
        shieldCore.setProtocolPaused(true);
        shieldCore.setProtocolPaused(false);

        // 验证可以激活 Shield
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        IShieldCore.ShieldConfig memory config = shieldCore.getShieldConfig(user1);
        assertTrue(config.isActive);
    }

    function test_GetShieldConfig_NotActive() public view {
        IShieldCore.ShieldConfig memory config = shieldCore.getShieldConfig(user1);
        assertFalse(config.isActive);
    }

    function test_CheckSpendingAllowed_WithWhitelist() public {
        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);
        // 添加一个地址到白名单
        shieldCore.addWhitelistedContract(address(weth));
        // 必须启用白名单模式才能生效
        shieldCore.enableWhitelistMode();

        // 验证白名单检查功能
        assertTrue(shieldCore.isWhitelisted(user1, address(weth)));
        assertFalse(shieldCore.isWhitelisted(user1, address(usdc)));
        vm.stopPrank();
    }

    function test_RecordSpending_WithWhitelistSet() public {
        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);
        // 添加一个非 USDC 地址到白名单
        shieldCore.addWhitelistedContract(address(weth));
        // 必须启用白名单模式才能生效
        shieldCore.enableWhitelistMode();
        vm.stopPrank();

        // 验证白名单状态
        assertTrue(shieldCore.isWhitelisted(user1, address(weth)));
        assertFalse(shieldCore.isWhitelisted(user1, address(usdc)));
    }

    function test_GetRemainingDailyAllowance_NotActive() public view {
        uint256 remaining = shieldCore.getRemainingDailyAllowance(user1, address(usdc));
        assertEq(remaining, 0);
    }


    function test_RecordSpending_WhilePaused_StillWorks() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        shieldCore.setProtocolPaused(true);

        // 注意：recordSpending 没有 whenNotPaused 修饰符
        // 只有 activateShield 有此限制
        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), 50e6);
    }

    function test_RevertWhen_ActivateWhilePaused() public {
        shieldCore.setProtocolPaused(true);

        vm.prank(user1);
        vm.expectRevert("Protocol paused");
        shieldCore.activateShield(1000e6, 100e6);
    }

    function test_RemoveTokenLimit_NotSet() public {
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        // 移除未设置的限额应该没有问题
        vm.prank(user1);
        shieldCore.removeTokenLimit(address(weth));
    }

    function test_GetTokenLimits() public {
        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);
        shieldCore.setTokenLimit(address(usdc), 500e6);
        shieldCore.setTokenLimit(address(weth), 1e18);
        vm.stopPrank();

        IShieldCore.TokenLimit memory limitUsdc = shieldCore.getTokenLimit(user1, address(usdc));
        IShieldCore.TokenLimit memory limitWeth = shieldCore.getTokenLimit(user1, address(weth));
        assertEq(limitUsdc.dailyLimit, 500e6);
        assertEq(limitWeth.dailyLimit, 1e18);
    }

    function test_RevertWhen_SetTokenLimitNotActive() public {
        vm.prank(user1);
        vm.expectRevert(IShieldCore.ShieldNotActive.selector);
        shieldCore.setTokenLimit(address(usdc), 500e6);
    }

    function test_RevertWhen_EnableEmergencyModeNotActive() public {
        vm.prank(user1);
        vm.expectRevert(IShieldCore.ShieldNotActive.selector);
        shieldCore.enableEmergencyMode();
    }

    function test_RevertWhen_DisableEmergencyModeNotActive() public {
        vm.prank(user1);
        vm.expectRevert(IShieldCore.ShieldNotActive.selector);
        shieldCore.disableEmergencyMode();
    }

    function test_RevertWhen_DisableEmergencyModeNotEnabled() public {
        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);

        vm.expectRevert("Not in emergency mode");
        shieldCore.disableEmergencyMode();
        vm.stopPrank();
    }

    function test_RecordSpending_WithTokenLimit() public {
        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);
        shieldCore.setTokenLimit(address(usdc), 200e6);
        vm.stopPrank();

        // 在限额内
        vm.prank(executor);
        shieldCore.recordSpending(user1, address(usdc), 50e6);
    }

    function test_RevertWhen_ExceedsTokenDailyLimit() public {
        vm.startPrank(user1);
        shieldCore.activateShield(1000e6, 100e6);
        shieldCore.setTokenLimit(address(usdc), 100e6);
        vm.stopPrank();

        vm.startPrank(executor);
        shieldCore.recordSpending(user1, address(usdc), 50e6);
        shieldCore.recordSpending(user1, address(usdc), 50e6);

        vm.expectRevert();
        shieldCore.recordSpending(user1, address(usdc), 10e6); // 超过每日限额
        vm.stopPrank();
    }
}

// 用于测试白名单的模拟合约
contract MockContract {
    function dummy() external pure returns (bool) {
        return true;
    }
}
