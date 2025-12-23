// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {SpendingLimitEnforcer} from "../src/caveats/SpendingLimitEnforcer.sol";
import {AllowedTargetsEnforcer} from "../src/caveats/AllowedTargetsEnforcer.sol";
import {TimeBoundEnforcer} from "../src/caveats/TimeBoundEnforcer.sol";

/**
 * @title SpendingLimitEnforcerTest
 * @notice SpendingLimitEnforcer 测试套件
 */
contract SpendingLimitEnforcerTest is Test {
    SpendingLimitEnforcer public enforcer;

    address public owner;
    address public authorizedCaller;
    address public unauthorizedCaller;
    address public delegator;
    address public redeemer;

    bytes32 public delegationHash;

    function setUp() public {
        owner = address(this);
        authorizedCaller = makeAddr("authorizedCaller");
        unauthorizedCaller = makeAddr("unauthorizedCaller");
        delegator = makeAddr("delegator");
        redeemer = makeAddr("redeemer");
        delegationHash = keccak256("testDelegation");

        enforcer = new SpendingLimitEnforcer();
        enforcer.addAuthorizedCaller(authorizedCaller);
    }

    // ==================== 访问控制测试 ====================

    function test_AddAuthorizedCaller() public {
        address newCaller = makeAddr("newCaller");
        enforcer.addAuthorizedCaller(newCaller);
        assertTrue(enforcer.authorizedCallers(newCaller));
    }

    function test_RemoveAuthorizedCaller() public {
        enforcer.removeAuthorizedCaller(authorizedCaller);
        assertFalse(enforcer.authorizedCallers(authorizedCaller));
    }

    function test_RevertWhen_UnauthorizedCallsBeforeHook() public {
        bytes memory terms = _encodeTerms(address(0x1), 100e6, 1000e6, 0);
        bytes memory args = abi.encode(50e6);

        vm.prank(unauthorizedCaller);
        vm.expectRevert(SpendingLimitEnforcer.UnauthorizedCaller.selector);
        enforcer.beforeHook(terms, args, 0, "", delegationHash, delegator, redeemer);
    }

    function test_RevertWhen_UnauthorizedCallsAfterHook() public {
        bytes memory terms = _encodeTerms(address(0x1), 100e6, 1000e6, 0);
        bytes memory args = abi.encode(50e6);

        vm.prank(unauthorizedCaller);
        vm.expectRevert(SpendingLimitEnforcer.UnauthorizedCaller.selector);
        enforcer.afterHook(terms, args, 0, "", delegationHash, delegator, redeemer);
    }

    // ==================== 限额检查测试 ====================

    function test_BeforeHook_WithinLimits() public {
        bytes memory terms = _encodeTerms(address(0x1), 100e6, 1000e6, 0);
        bytes memory args = abi.encode(50e6);

        vm.prank(authorizedCaller);
        enforcer.beforeHook(terms, args, 0, "", delegationHash, delegator, redeemer);
        // 不应该 revert
    }

    function test_RevertWhen_ExceedsSingleTxLimit() public {
        bytes memory terms = _encodeTerms(address(0x1), 100e6, 1000e6, 0);
        bytes memory args = abi.encode(150e6); // 超过单笔限额

        vm.prank(authorizedCaller);
        vm.expectRevert(abi.encodeWithSelector(
            SpendingLimitEnforcer.ExceedsSingleTxLimit.selector,
            150e6,
            100e6
        ));
        enforcer.beforeHook(terms, args, 0, "", delegationHash, delegator, redeemer);
    }

    function test_RevertWhen_ExceedsDailyLimit() public {
        bytes memory terms = _encodeTerms(address(0x1), 100e6, 200e6, 0);
        bytes memory args = abi.encode(100e6);

        // 第一次支出
        vm.prank(authorizedCaller);
        enforcer.beforeHook(terms, args, 0, "", delegationHash, delegator, redeemer);
        vm.prank(authorizedCaller);
        enforcer.afterHook(terms, args, 0, "", delegationHash, delegator, redeemer);

        // 第二次支出
        vm.prank(authorizedCaller);
        enforcer.beforeHook(terms, args, 0, "", delegationHash, delegator, redeemer);
        vm.prank(authorizedCaller);
        enforcer.afterHook(terms, args, 0, "", delegationHash, delegator, redeemer);

        // 第三次应该失败 (已用 200e6，剩余 0)
        vm.prank(authorizedCaller);
        vm.expectRevert(abi.encodeWithSelector(
            SpendingLimitEnforcer.ExceedsDailyLimit.selector,
            100e6,
            0
        ));
        enforcer.beforeHook(terms, args, 0, "", delegationHash, delegator, redeemer);
    }

    function test_RevertWhen_ExceedsTotalLimit() public {
        bytes memory terms = _encodeTerms(address(0x1), 100e6, 1000e6, 150e6); // 总限额 150
        bytes memory args = abi.encode(100e6);

        // 第一次支出
        vm.prank(authorizedCaller);
        enforcer.beforeHook(terms, args, 0, "", delegationHash, delegator, redeemer);
        vm.prank(authorizedCaller);
        enforcer.afterHook(terms, args, 0, "", delegationHash, delegator, redeemer);

        // 第二次应该失败 (已用 100e6，剩余 50e6)
        vm.prank(authorizedCaller);
        vm.expectRevert(abi.encodeWithSelector(
            SpendingLimitEnforcer.ExceedsTotalLimit.selector,
            100e6,
            50e6
        ));
        enforcer.beforeHook(terms, args, 0, "", delegationHash, delegator, redeemer);
    }

    // ==================== 状态更新测试 ====================

    function test_AfterHook_UpdatesState() public {
        bytes memory terms = _encodeTerms(address(0x1), 100e6, 1000e6, 0);
        bytes memory args = abi.encode(50e6);

        vm.prank(authorizedCaller);
        enforcer.beforeHook(terms, args, 0, "", delegationHash, delegator, redeemer);
        vm.prank(authorizedCaller);
        enforcer.afterHook(terms, args, 0, "", delegationHash, delegator, redeemer);

        SpendingLimitEnforcer.UsageState memory state = enforcer.getUsageState(delegationHash);
        assertEq(state.spentToday, 50e6);
        assertEq(state.totalSpent, 50e6);
    }

    function test_DailyReset() public {
        bytes memory terms = _encodeTerms(address(0x1), 100e6, 200e6, 0);
        bytes memory args = abi.encode(100e6);

        // 第一天支出
        vm.prank(authorizedCaller);
        enforcer.beforeHook(terms, args, 0, "", delegationHash, delegator, redeemer);
        vm.prank(authorizedCaller);
        enforcer.afterHook(terms, args, 0, "", delegationHash, delegator, redeemer);

        SpendingLimitEnforcer.UsageState memory state1 = enforcer.getUsageState(delegationHash);
        assertEq(state1.spentToday, 100e6);

        // 快进一天
        vm.warp(block.timestamp + 1 days);

        // 第二天支出
        vm.prank(authorizedCaller);
        enforcer.beforeHook(terms, args, 0, "", delegationHash, delegator, redeemer);
        vm.prank(authorizedCaller);
        enforcer.afterHook(terms, args, 0, "", delegationHash, delegator, redeemer);

        SpendingLimitEnforcer.UsageState memory state2 = enforcer.getUsageState(delegationHash);
        assertEq(state2.spentToday, 100e6); // 重置后的新支出
        assertEq(state2.totalSpent, 200e6); // 总计累加
    }

    // ==================== 视图函数测试 ====================

    function test_GetRemainingAllowance() public {
        bytes memory terms = _encodeTerms(address(0x1), 100e6, 500e6, 1000e6);
        bytes memory args = abi.encode(100e6);

        // 支出 100e6
        vm.prank(authorizedCaller);
        enforcer.beforeHook(terms, args, 0, "", delegationHash, delegator, redeemer);
        vm.prank(authorizedCaller);
        enforcer.afterHook(terms, args, 0, "", delegationHash, delegator, redeemer);

        (uint256 dailyRemaining, uint256 totalRemaining) = enforcer.getRemainingAllowance(delegationHash, terms);
        assertEq(dailyRemaining, 400e6);
        assertEq(totalRemaining, 900e6);
    }

    function test_EncodeTerms() public view {
        bytes memory encoded = enforcer.encodeTerms(address(0x1), 100e6, 500e6, 1000e6);
        assertTrue(encoded.length >= 128);
    }

    // ==================== 辅助函数 ====================

    function _encodeTerms(
        address token,
        uint256 singleTxLimit,
        uint256 dailyLimit,
        uint256 totalLimit
    ) internal pure returns (bytes memory) {
        return abi.encode(SpendingLimitEnforcer.LimitTerms({
            token: token,
            singleTxLimit: singleTxLimit,
            dailyLimit: dailyLimit,
            totalLimit: totalLimit
        }));
    }
}

/**
 * @title AllowedTargetsEnforcerTest
 * @notice AllowedTargetsEnforcer 测试套件
 */
contract AllowedTargetsEnforcerTest is Test {
    AllowedTargetsEnforcer public enforcer;

    address public owner;
    address public authorizedCaller;
    address public delegator;
    address public redeemer;

    address public target1;
    address public target2;
    address public target3;

    bytes32 public delegationHash;

    function setUp() public {
        owner = address(this);
        authorizedCaller = makeAddr("authorizedCaller");
        delegator = makeAddr("delegator");
        redeemer = makeAddr("redeemer");
        target1 = makeAddr("target1");
        target2 = makeAddr("target2");
        target3 = makeAddr("target3");
        delegationHash = keccak256("testDelegation");

        enforcer = new AllowedTargetsEnforcer();
        enforcer.addAuthorizedCaller(authorizedCaller);
    }

    // ==================== 访问控制测试 ====================

    function test_RevertWhen_UnauthorizedCaller() public {
        address[] memory targets = new address[](1);
        targets[0] = target1;
        bytes memory terms = enforcer.encodeWhitelistTerms(targets);

        bytes memory executionCalldata = abi.encodePacked(target1);

        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(AllowedTargetsEnforcer.UnauthorizedCaller.selector);
        enforcer.beforeHook(terms, "", 0, executionCalldata, delegationHash, delegator, redeemer);
    }

    // ==================== 白名单模式测试 ====================

    function test_WhitelistMode_AllowedTarget() public {
        address[] memory targets = new address[](2);
        targets[0] = target1;
        targets[1] = target2;
        bytes memory terms = enforcer.encodeWhitelistTerms(targets);

        bytes memory executionCalldata = abi.encodePacked(target1);

        vm.prank(authorizedCaller);
        enforcer.beforeHook(terms, "", 0, executionCalldata, delegationHash, delegator, redeemer);
        // 不应该 revert
    }

    function test_RevertWhen_WhitelistMode_BlockedTarget() public {
        address[] memory targets = new address[](2);
        targets[0] = target1;
        targets[1] = target2;
        bytes memory terms = enforcer.encodeWhitelistTerms(targets);

        bytes memory executionCalldata = abi.encodePacked(target3); // 不在白名单中

        vm.prank(authorizedCaller);
        vm.expectRevert(abi.encodeWithSelector(
            AllowedTargetsEnforcer.TargetNotAllowed.selector,
            target3
        ));
        enforcer.beforeHook(terms, "", 0, executionCalldata, delegationHash, delegator, redeemer);
    }

    // ==================== 黑名单模式测试 ====================

    function test_BlacklistMode_AllowedTarget() public {
        address[] memory targets = new address[](1);
        targets[0] = target1;
        bytes memory terms = enforcer.encodeBlacklistTerms(targets);

        bytes memory executionCalldata = abi.encodePacked(target2); // 不在黑名单中

        vm.prank(authorizedCaller);
        enforcer.beforeHook(terms, "", 0, executionCalldata, delegationHash, delegator, redeemer);
        // 不应该 revert
    }

    function test_RevertWhen_BlacklistMode_BlockedTarget() public {
        address[] memory targets = new address[](1);
        targets[0] = target1;
        bytes memory terms = enforcer.encodeBlacklistTerms(targets);

        bytes memory executionCalldata = abi.encodePacked(target1); // 在黑名单中

        vm.prank(authorizedCaller);
        vm.expectRevert(abi.encodeWithSelector(
            AllowedTargetsEnforcer.TargetBlacklisted.selector,
            target1
        ));
        enforcer.beforeHook(terms, "", 0, executionCalldata, delegationHash, delegator, redeemer);
    }

    // ==================== 视图函数测试 ====================

    function test_ValidateTarget_Whitelist() public {
        address[] memory targets = new address[](1);
        targets[0] = target1;
        bytes memory terms = enforcer.encodeWhitelistTerms(targets);

        (bool allowed1, string memory reason1) = enforcer.validateTarget(terms, target1);
        assertTrue(allowed1);
        assertEq(reason1, "Target is whitelisted");

        (bool allowed2, string memory reason2) = enforcer.validateTarget(terms, target2);
        assertFalse(allowed2);
        assertEq(reason2, "Target not in whitelist");
    }

    function test_ValidateTarget_Blacklist() public {
        address[] memory targets = new address[](1);
        targets[0] = target1;
        bytes memory terms = enforcer.encodeBlacklistTerms(targets);

        (bool allowed1, string memory reason1) = enforcer.validateTarget(terms, target1);
        assertFalse(allowed1);
        assertEq(reason1, "Target is blacklisted");

        (bool allowed2, string memory reason2) = enforcer.validateTarget(terms, target2);
        assertTrue(allowed2);
        assertEq(reason2, "Target not in blacklist");
    }

    function test_RevertWhen_EmptyTargetList() public {
        address[] memory targets = new address[](0);

        vm.expectRevert(AllowedTargetsEnforcer.EmptyTargetList.selector);
        enforcer.encodeWhitelistTerms(targets);
    }

    // ==================== 补充覆盖测试 ====================

    function test_AddAuthorizedCaller() public {
        address newCaller = makeAddr("newCaller");
        enforcer.addAuthorizedCaller(newCaller);

        // 新调用者应该可以调用
        address[] memory targets = new address[](1);
        targets[0] = target1;
        bytes memory terms = enforcer.encodeWhitelistTerms(targets);
        bytes memory executionCalldata = abi.encodePacked(target1);

        vm.prank(newCaller);
        enforcer.beforeHook(terms, "", 0, executionCalldata, delegationHash, delegator, redeemer);
    }

    function test_RemoveAuthorizedCaller() public {
        enforcer.removeAuthorizedCaller(authorizedCaller);

        address[] memory targets = new address[](1);
        targets[0] = target1;
        bytes memory terms = enforcer.encodeWhitelistTerms(targets);
        bytes memory executionCalldata = abi.encodePacked(target1);

        vm.prank(authorizedCaller);
        vm.expectRevert(AllowedTargetsEnforcer.UnauthorizedCaller.selector);
        enforcer.beforeHook(terms, "", 0, executionCalldata, delegationHash, delegator, redeemer);
    }

    function test_GetTargets_Whitelist() public {
        address[] memory targets = new address[](2);
        targets[0] = target1;
        targets[1] = target2;
        bytes memory terms = enforcer.encodeWhitelistTerms(targets);

        // 验证 terms 长度有效
        assertTrue(terms.length > 0);
    }

    function test_GetTargets_Blacklist() public {
        address[] memory targets = new address[](1);
        targets[0] = target1;
        bytes memory terms = enforcer.encodeBlacklistTerms(targets);

        // 验证 terms 长度有效
        assertTrue(terms.length > 0);
    }
}

/**
 * @title TimeBoundEnforcerTest
 * @notice TimeBoundEnforcer 测试套件
 */
contract TimeBoundEnforcerTest is Test {
    TimeBoundEnforcer public enforcer;

    address public owner;
    address public authorizedCaller;
    address public delegator;
    address public redeemer;

    bytes32 public delegationHash;

    function setUp() public {
        owner = address(this);
        authorizedCaller = makeAddr("authorizedCaller");
        delegator = makeAddr("delegator");
        redeemer = makeAddr("redeemer");
        delegationHash = keccak256("testDelegation");

        enforcer = new TimeBoundEnforcer();
        enforcer.addAuthorizedCaller(authorizedCaller);
    }

    // ==================== 访问控制测试 ====================

    function test_RevertWhen_UnauthorizedCaller() public {
        bytes memory terms = enforcer.encodeTerms(0, 0, 0);

        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(TimeBoundEnforcer.UnauthorizedCaller.selector);
        enforcer.beforeHook(terms, "", 0, "", delegationHash, delegator, redeemer);
    }

    // ==================== 时间范围测试 ====================

    function test_BeforeHook_WithinTimeRange() public {
        uint256 notBefore = block.timestamp;
        uint256 notAfter = block.timestamp + 7 days;
        bytes memory terms = enforcer.encodeTerms(notBefore, notAfter, 0);

        vm.prank(authorizedCaller);
        enforcer.beforeHook(terms, "", 0, "", delegationHash, delegator, redeemer);
        // 不应该 revert
    }

    function test_RevertWhen_TooEarly() public {
        uint256 notBefore = block.timestamp + 1 days;
        uint256 notAfter = block.timestamp + 7 days;
        bytes memory terms = enforcer.encodeTerms(notBefore, notAfter, 0);

        vm.prank(authorizedCaller);
        vm.expectRevert(abi.encodeWithSelector(
            TimeBoundEnforcer.TooEarly.selector,
            notBefore,
            block.timestamp
        ));
        enforcer.beforeHook(terms, "", 0, "", delegationHash, delegator, redeemer);
    }

    function test_RevertWhen_TooLate() public {
        uint256 notBefore = block.timestamp;
        uint256 notAfter = block.timestamp + 1 days;
        bytes memory terms = enforcer.encodeTerms(notBefore, notAfter, 0);

        // 快进超过结束时间
        vm.warp(block.timestamp + 2 days);

        vm.prank(authorizedCaller);
        vm.expectRevert(abi.encodeWithSelector(
            TimeBoundEnforcer.TooLate.selector,
            notAfter,
            block.timestamp
        ));
        enforcer.beforeHook(terms, "", 0, "", delegationHash, delegator, redeemer);
    }

    // ==================== 执行次数测试 ====================

    function test_MaxExecutions() public {
        bytes memory terms = enforcer.encodeTerms(0, 0, 3); // 最多 3 次

        // 执行 3 次
        for (uint i = 0; i < 3; i++) {
            vm.prank(authorizedCaller);
            enforcer.beforeHook(terms, "", 0, "", delegationHash, delegator, redeemer);
            vm.prank(authorizedCaller);
            enforcer.afterHook(terms, "", 0, "", delegationHash, delegator, redeemer);
        }

        assertEq(enforcer.getExecutionCount(delegationHash), 3);

        // 第 4 次应该失败
        vm.prank(authorizedCaller);
        vm.expectRevert(abi.encodeWithSelector(
            TimeBoundEnforcer.MaxExecutionsReached.selector,
            3,
            3
        ));
        enforcer.beforeHook(terms, "", 0, "", delegationHash, delegator, redeemer);
    }

    function test_AfterHook_IncrementsCounter() public {
        bytes memory terms = enforcer.encodeTerms(0, 0, 10);

        vm.prank(authorizedCaller);
        enforcer.beforeHook(terms, "", 0, "", delegationHash, delegator, redeemer);
        vm.prank(authorizedCaller);
        enforcer.afterHook(terms, "", 0, "", delegationHash, delegator, redeemer);

        assertEq(enforcer.getExecutionCount(delegationHash), 1);
    }

    // ==================== 视图函数测试 ====================

    function test_IsStillValid() public {
        uint256 notBefore = block.timestamp;
        uint256 notAfter = block.timestamp + 7 days;
        bytes memory terms = enforcer.encodeTerms(notBefore, notAfter, 5);

        (bool valid, string memory reason) = enforcer.isStillValid(delegationHash, terms);
        assertTrue(valid);
        assertEq(reason, "Valid");
    }

    function test_IsStillValid_NotStarted() public {
        uint256 notBefore = block.timestamp + 1 days;
        bytes memory terms = enforcer.encodeTerms(notBefore, 0, 0);

        (bool valid, string memory reason) = enforcer.isStillValid(delegationHash, terms);
        assertFalse(valid);
        assertEq(reason, "Not started yet");
    }

    function test_IsStillValid_Expired() public {
        uint256 notAfter = block.timestamp + 1 days;
        bytes memory terms = enforcer.encodeTerms(0, notAfter, 0);

        vm.warp(block.timestamp + 2 days);

        (bool valid, string memory reason) = enforcer.isStillValid(delegationHash, terms);
        assertFalse(valid);
        assertEq(reason, "Expired");
    }

    function test_GetRemainingTime() public {
        uint256 notAfter = block.timestamp + 7 days;
        bytes memory terms = enforcer.encodeTerms(0, notAfter, 0);

        uint256 remaining = enforcer.getRemainingTime(terms);
        assertEq(remaining, 7 days);

        vm.warp(block.timestamp + 3 days);
        remaining = enforcer.getRemainingTime(terms);
        assertEq(remaining, 4 days);
    }

    function test_GetRemainingTime_NoLimit() public {
        bytes memory terms = enforcer.encodeTerms(0, 0, 0);

        uint256 remaining = enforcer.getRemainingTime(terms);
        assertEq(remaining, type(uint256).max);
    }

    function test_GetRemainingExecutions() public {
        bytes memory terms = enforcer.encodeTerms(0, 0, 5);

        uint256 remaining = enforcer.getRemainingExecutions(delegationHash, terms);
        assertEq(remaining, 5);

        // 执行 2 次
        for (uint i = 0; i < 2; i++) {
            vm.prank(authorizedCaller);
            enforcer.beforeHook(terms, "", 0, "", delegationHash, delegator, redeemer);
            vm.prank(authorizedCaller);
            enforcer.afterHook(terms, "", 0, "", delegationHash, delegator, redeemer);
        }

        remaining = enforcer.getRemainingExecutions(delegationHash, terms);
        assertEq(remaining, 3);
    }

    function test_EncodeWithDuration() public {
        bytes memory terms = enforcer.encodeWithDuration(7 days, 10);
        assertTrue(terms.length >= 96);
    }

    function test_RevertWhen_InvalidTimeRange() public {
        vm.expectRevert(TimeBoundEnforcer.InvalidTimeRange.selector);
        enforcer.encodeTerms(1000, 500, 0); // notBefore > notAfter
    }

    // ==================== 补充覆盖测试 ====================

    function test_AddAuthorizedCaller() public {
        address newCaller = makeAddr("newCaller");
        enforcer.addAuthorizedCaller(newCaller);

        bytes memory terms = enforcer.encodeTerms(0, 0, 0);

        vm.prank(newCaller);
        enforcer.beforeHook(terms, "", 0, "", delegationHash, delegator, redeemer);
    }

    function test_RemoveAuthorizedCaller() public {
        enforcer.removeAuthorizedCaller(authorizedCaller);

        bytes memory terms = enforcer.encodeTerms(0, 0, 0);

        vm.prank(authorizedCaller);
        vm.expectRevert(TimeBoundEnforcer.UnauthorizedCaller.selector);
        enforcer.beforeHook(terms, "", 0, "", delegationHash, delegator, redeemer);
    }

    function test_BeforeHook_UnlimitedExecutions() public {
        // maxExecutions = 0 means unlimited
        bytes memory terms = enforcer.encodeTerms(0, 0, 0);

        // Should be able to call many times
        for (uint i = 0; i < 5; i++) {
            vm.prank(authorizedCaller);
            enforcer.beforeHook(terms, "", 0, "", delegationHash, delegator, redeemer);
        }
    }

    function test_GetTimeRange() public view {
        uint256 notBefore = block.timestamp;
        uint256 notAfter = block.timestamp + 7 days;
        bytes memory terms = enforcer.encodeTerms(notBefore, notAfter, 10);

        // Decode the terms to verify encoding
        (uint256 nb, uint256 na, uint256 max) = abi.decode(terms, (uint256, uint256, uint256));
        assertEq(nb, notBefore);
        assertEq(na, notAfter);
        assertEq(max, 10);
    }

    function test_NoTimeRestrictions() public {
        // notBefore = 0, notAfter = 0 means no time restrictions
        bytes memory terms = enforcer.encodeTerms(0, 0, 0);

        vm.prank(authorizedCaller);
        enforcer.beforeHook(terms, "", 0, "", delegationHash, delegator, redeemer);

        // Fast forward and still should work
        vm.warp(block.timestamp + 365 days);

        vm.prank(authorizedCaller);
        enforcer.beforeHook(terms, "", 0, "", delegationHash, delegator, redeemer);
    }
}
