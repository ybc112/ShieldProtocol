// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ShieldCore} from "../src/core/ShieldCore.sol";
import {SubscriptionManager} from "../src/subscriptions/SubscriptionManager.sol";
import {ISubscriptionManager} from "../src/interfaces/ISubscriptionManager.sol";
import {IShieldCore} from "../src/interfaces/IShieldCore.sol";
import {MockERC20} from "./mocks/Mocks.sol";

/**
 * @title SubscriptionManagerTest
 * @notice SubscriptionManager 合约完整测试套件
 */
contract SubscriptionManagerTest is Test {
    ShieldCore public shieldCore;
    SubscriptionManager public subscriptionManager;
    MockERC20 public usdc;

    address public owner;
    address public subscriber;
    address public recipient;
    address public keeper;

    // 事件定义
    event SubscriptionCreated(
        bytes32 indexed subscriptionId,
        address indexed subscriber,
        address indexed recipient,
        address token,
        uint256 amount,
        ISubscriptionManager.BillingPeriod billingPeriod
    );
    event PaymentExecuted(
        bytes32 indexed subscriptionId,
        address indexed subscriber,
        address indexed recipient,
        uint256 amount,
        uint256 paymentNumber,
        uint256 timestamp
    );
    event SubscriptionPaused(bytes32 indexed subscriptionId, uint256 timestamp);
    event SubscriptionResumed(bytes32 indexed subscriptionId, uint256 timestamp);
    event SubscriptionCancelled(bytes32 indexed subscriptionId, uint256 paymentsCompleted, uint256 timestamp);

    function setUp() public {
        owner = address(this);
        subscriber = makeAddr("subscriber");
        recipient = makeAddr("recipient");
        keeper = makeAddr("keeper");

        // 部署合约
        shieldCore = new ShieldCore();
        subscriptionManager = new SubscriptionManager(address(shieldCore));

        // 部署 Mock 代币
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // 配置授权
        shieldCore.addAuthorizedExecutor(address(subscriptionManager));

        // 给用户铸造代币
        usdc.mint(subscriber, 10000e6);

        // 用户激活 Shield
        vm.prank(subscriber);
        shieldCore.activateShield(1000e6, 100e6);
    }

    // ==================== 创建订阅测试 ====================

    function test_CreateSubscription_Success() public {
        vm.startPrank(subscriber);
        usdc.approve(address(subscriptionManager), type(uint256).max);

        ISubscriptionManager.CreateSubscriptionParams memory params = ISubscriptionManager.CreateSubscriptionParams({
            recipient: recipient,
            token: address(usdc),
            amount: 10e6,
            billingPeriod: ISubscriptionManager.BillingPeriod.Monthly,
            maxPayments: 12,
            executeFirstPayment: false
        });

        bytes32 subscriptionId = subscriptionManager.createSubscription(params);
        vm.stopPrank();

        ISubscriptionManager.Subscription memory sub = subscriptionManager.getSubscription(subscriptionId);
        assertEq(sub.subscriber, subscriber);
        assertEq(sub.recipient, recipient);
        assertEq(sub.amount, 10e6);
        assertEq(sub.maxPayments, 12);
        assertEq(uint(sub.status), uint(ISubscriptionManager.SubscriptionStatus.Active));
    }

    function test_CreateSubscription_WithFirstPayment() public {
        vm.startPrank(subscriber);
        usdc.approve(address(subscriptionManager), type(uint256).max);

        uint256 balanceBefore = usdc.balanceOf(subscriber);

        ISubscriptionManager.CreateSubscriptionParams memory params = ISubscriptionManager.CreateSubscriptionParams({
            recipient: recipient,
            token: address(usdc),
            amount: 10e6,
            billingPeriod: ISubscriptionManager.BillingPeriod.Monthly,
            maxPayments: 12,
            executeFirstPayment: true
        });

        bytes32 subscriptionId = subscriptionManager.createSubscription(params);
        vm.stopPrank();

        ISubscriptionManager.Subscription memory sub = subscriptionManager.getSubscription(subscriptionId);
        assertEq(sub.paymentsCompleted, 1);
        assertTrue(usdc.balanceOf(subscriber) < balanceBefore);
        assertTrue(usdc.balanceOf(recipient) > 0);
    }

    function test_CreateSubscription_Unlimited() public {
        vm.startPrank(subscriber);
        usdc.approve(address(subscriptionManager), type(uint256).max);

        ISubscriptionManager.CreateSubscriptionParams memory params = ISubscriptionManager.CreateSubscriptionParams({
            recipient: recipient,
            token: address(usdc),
            amount: 10e6,
            billingPeriod: ISubscriptionManager.BillingPeriod.Monthly,
            maxPayments: 0, // 无限
            executeFirstPayment: false
        });

        bytes32 subscriptionId = subscriptionManager.createSubscription(params);
        vm.stopPrank();

        ISubscriptionManager.Subscription memory sub = subscriptionManager.getSubscription(subscriptionId);
        assertEq(sub.maxPayments, 0);
    }

    function test_RevertWhen_SelfSubscribe() public {
        vm.startPrank(subscriber);

        ISubscriptionManager.CreateSubscriptionParams memory params = ISubscriptionManager.CreateSubscriptionParams({
            recipient: subscriber, // 自己订阅自己
            token: address(usdc),
            amount: 10e6,
            billingPeriod: ISubscriptionManager.BillingPeriod.Monthly,
            maxPayments: 12,
            executeFirstPayment: false
        });

        vm.expectRevert(ISubscriptionManager.InvalidRecipient.selector);
        subscriptionManager.createSubscription(params);
        vm.stopPrank();
    }

    function test_RevertWhen_ZeroAmount() public {
        vm.startPrank(subscriber);

        ISubscriptionManager.CreateSubscriptionParams memory params = ISubscriptionManager.CreateSubscriptionParams({
            recipient: recipient,
            token: address(usdc),
            amount: 0,
            billingPeriod: ISubscriptionManager.BillingPeriod.Monthly,
            maxPayments: 12,
            executeFirstPayment: false
        });

        vm.expectRevert(ISubscriptionManager.InvalidAmount.selector);
        subscriptionManager.createSubscription(params);
        vm.stopPrank();
    }

    function test_RevertWhen_ZeroRecipient() public {
        vm.startPrank(subscriber);

        ISubscriptionManager.CreateSubscriptionParams memory params = ISubscriptionManager.CreateSubscriptionParams({
            recipient: address(0),
            token: address(usdc),
            amount: 10e6,
            billingPeriod: ISubscriptionManager.BillingPeriod.Monthly,
            maxPayments: 12,
            executeFirstPayment: false
        });

        vm.expectRevert(ISubscriptionManager.InvalidRecipient.selector);
        subscriptionManager.createSubscription(params);
        vm.stopPrank();
    }

    // ==================== 执行支付测试 ====================

    function test_ExecutePayment_Success() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 10e6, false);

        vm.prank(subscriber);
        usdc.approve(address(subscriptionManager), type(uint256).max);

        uint256 recipientBalanceBefore = usdc.balanceOf(recipient);

        // 跳过到下次支付时间
        ISubscriptionManager.Subscription memory sub = subscriptionManager.getSubscription(subscriptionId);
        vm.warp(sub.nextPaymentTime);

        subscriptionManager.executePayment(subscriptionId);

        sub = subscriptionManager.getSubscription(subscriptionId);
        assertEq(sub.paymentsCompleted, 1);
        assertTrue(usdc.balanceOf(recipient) > recipientBalanceBefore);
    }

    function test_ExecutePayment_MultiplePayments() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 10e6, false);

        vm.prank(subscriber);
        usdc.approve(address(subscriptionManager), type(uint256).max);

        // 跳过到第一次支付时间
        ISubscriptionManager.Subscription memory sub = subscriptionManager.getSubscription(subscriptionId);
        vm.warp(sub.nextPaymentTime);

        // 执行第一次
        subscriptionManager.executePayment(subscriptionId);

        sub = subscriptionManager.getSubscription(subscriptionId);
        assertEq(sub.paymentsCompleted, 1);

        // 快进一个月
        vm.warp(sub.nextPaymentTime);

        // 执行第二次
        subscriptionManager.executePayment(subscriptionId);

        sub = subscriptionManager.getSubscription(subscriptionId);
        assertEq(sub.paymentsCompleted, 2);
    }

    function test_RevertWhen_PaymentNotDue() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 10e6, false);

        vm.prank(subscriber);
        usdc.approve(address(subscriptionManager), type(uint256).max);

        // 跳过到第一次支付时间
        ISubscriptionManager.Subscription memory sub = subscriptionManager.getSubscription(subscriptionId);
        vm.warp(sub.nextPaymentTime);

        // 执行第一次
        subscriptionManager.executePayment(subscriptionId);

        // 立即尝试再次执行（不跳过时间）
        sub = subscriptionManager.getSubscription(subscriptionId);
        vm.expectRevert(abi.encodeWithSelector(
            ISubscriptionManager.PaymentNotDue.selector,
            sub.nextPaymentTime
        ));
        subscriptionManager.executePayment(subscriptionId);
    }

    function test_RevertWhen_MaxPaymentsReached() public {
        // 创建只有 2 次支付的订阅
        vm.startPrank(subscriber);
        usdc.approve(address(subscriptionManager), type(uint256).max);

        ISubscriptionManager.CreateSubscriptionParams memory params = ISubscriptionManager.CreateSubscriptionParams({
            recipient: recipient,
            token: address(usdc),
            amount: 10e6,
            billingPeriod: ISubscriptionManager.BillingPeriod.Daily,
            maxPayments: 2,
            executeFirstPayment: false
        });

        bytes32 subscriptionId = subscriptionManager.createSubscription(params);
        vm.stopPrank();

        // 跳过到第一次支付时间
        ISubscriptionManager.Subscription memory sub = subscriptionManager.getSubscription(subscriptionId);
        vm.warp(sub.nextPaymentTime);

        // 执行两次
        subscriptionManager.executePayment(subscriptionId);
        sub = subscriptionManager.getSubscription(subscriptionId);
        vm.warp(sub.nextPaymentTime);
        subscriptionManager.executePayment(subscriptionId);

        // 第三次应该失败 - 订阅状态已变为 Expired
        // 因为状态检查在 MaxPayments 检查之前，所以会抛出 SubscriptionNotActive
        sub = subscriptionManager.getSubscription(subscriptionId);
        vm.warp(sub.nextPaymentTime);
        vm.expectRevert(ISubscriptionManager.SubscriptionNotActive.selector);
        subscriptionManager.executePayment(subscriptionId);
    }

    function test_ExecutePayment_WithProtocolFee() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 100e6, false);

        vm.prank(subscriber);
        usdc.approve(address(subscriptionManager), type(uint256).max);

        uint256 feeRecipientBalanceBefore = usdc.balanceOf(address(this)); // owner is fee recipient
        uint256 recipientBalanceBefore = usdc.balanceOf(recipient);

        // 跳过到下次支付时间
        ISubscriptionManager.Subscription memory sub = subscriptionManager.getSubscription(subscriptionId);
        vm.warp(sub.nextPaymentTime);

        subscriptionManager.executePayment(subscriptionId);

        // 验证手续费 (0.5% = 50 bps)
        uint256 expectedFee = (100e6 * 50) / 10000; // 0.5 USDC
        uint256 expectedRecipientAmount = 100e6 - expectedFee;

        assertEq(usdc.balanceOf(address(this)) - feeRecipientBalanceBefore, expectedFee);
        assertEq(usdc.balanceOf(recipient) - recipientBalanceBefore, expectedRecipientAmount);
    }

    // ==================== 暂停/恢复/取消测试 ====================

    function test_PauseSubscription() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 10e6, false);

        vm.prank(subscriber);
        vm.expectEmit(true, false, false, true);
        emit SubscriptionPaused(subscriptionId, block.timestamp);
        subscriptionManager.pauseSubscription(subscriptionId);

        ISubscriptionManager.Subscription memory sub = subscriptionManager.getSubscription(subscriptionId);
        assertEq(uint(sub.status), uint(ISubscriptionManager.SubscriptionStatus.Paused));
    }

    function test_ResumeSubscription() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 10e6, false);

        vm.startPrank(subscriber);
        subscriptionManager.pauseSubscription(subscriptionId);

        vm.expectEmit(true, false, false, true);
        emit SubscriptionResumed(subscriptionId, block.timestamp);
        subscriptionManager.resumeSubscription(subscriptionId);
        vm.stopPrank();

        ISubscriptionManager.Subscription memory sub = subscriptionManager.getSubscription(subscriptionId);
        assertEq(uint(sub.status), uint(ISubscriptionManager.SubscriptionStatus.Active));
    }

    function test_CancelSubscription() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 10e6, false);

        vm.prank(subscriber);
        subscriptionManager.cancelSubscription(subscriptionId);

        ISubscriptionManager.Subscription memory sub = subscriptionManager.getSubscription(subscriptionId);
        assertEq(uint(sub.status), uint(ISubscriptionManager.SubscriptionStatus.Cancelled));
        assertTrue(sub.cancelledAt > 0);
    }

    function test_RevertWhen_NonSubscriberPauses() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 10e6, false);

        vm.prank(recipient);
        vm.expectRevert(ISubscriptionManager.NotSubscriber.selector);
        subscriptionManager.pauseSubscription(subscriptionId);
    }

    function test_RevertWhen_ExecutePausedSubscription() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 10e6, false);

        vm.prank(subscriber);
        usdc.approve(address(subscriptionManager), type(uint256).max);

        vm.prank(subscriber);
        subscriptionManager.pauseSubscription(subscriptionId);

        vm.expectRevert(ISubscriptionManager.SubscriptionNotActive.selector);
        subscriptionManager.executePayment(subscriptionId);
    }

    // ==================== 更新订阅测试 ====================

    function test_UpdateSubscriptionAmount() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 10e6, false);

        vm.prank(subscriber);
        subscriptionManager.updateSubscriptionAmount(subscriptionId, 20e6);

        ISubscriptionManager.Subscription memory sub = subscriptionManager.getSubscription(subscriptionId);
        assertEq(sub.amount, 20e6);
    }

    function test_RevertWhen_UpdateToZeroAmount() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 10e6, false);

        vm.prank(subscriber);
        vm.expectRevert(ISubscriptionManager.InvalidAmount.selector);
        subscriptionManager.updateSubscriptionAmount(subscriptionId, 0);
    }

    // ==================== 批量执行测试 ====================

    function test_BatchExecutePayments() public {
        // 创建多个订阅
        bytes32 sub1 = _createSubscription(subscriber, recipient, 10e6, false);

        address recipient2 = makeAddr("recipient2");
        ISubscriptionManager.CreateSubscriptionParams memory params = ISubscriptionManager.CreateSubscriptionParams({
            recipient: recipient2,
            token: address(usdc),
            amount: 15e6,
            billingPeriod: ISubscriptionManager.BillingPeriod.Monthly,
            maxPayments: 12,
            executeFirstPayment: false
        });
        vm.prank(subscriber);
        bytes32 sub2 = subscriptionManager.createSubscription(params);

        vm.prank(subscriber);
        usdc.approve(address(subscriptionManager), type(uint256).max);

        // 跳过到支付时间
        ISubscriptionManager.Subscription memory subData = subscriptionManager.getSubscription(sub1);
        vm.warp(subData.nextPaymentTime);

        bytes32[] memory subscriptionIds = new bytes32[](2);
        subscriptionIds[0] = sub1;
        subscriptionIds[1] = sub2;

        subscriptionManager.batchExecutePayments(subscriptionIds);

        ISubscriptionManager.Subscription memory s1 = subscriptionManager.getSubscription(sub1);
        ISubscriptionManager.Subscription memory s2 = subscriptionManager.getSubscription(sub2);

        assertEq(s1.paymentsCompleted, 1);
        assertEq(s2.paymentsCompleted, 1);
    }

    // ==================== 视图函数测试 ====================

    function test_GetPendingPayments() public {
        bytes32 sub1 = _createSubscription(subscriber, recipient, 10e6, false);

        address recipient2 = makeAddr("recipient2");
        ISubscriptionManager.CreateSubscriptionParams memory params = ISubscriptionManager.CreateSubscriptionParams({
            recipient: recipient2,
            token: address(usdc),
            amount: 15e6,
            billingPeriod: ISubscriptionManager.BillingPeriod.Monthly,
            maxPayments: 12,
            executeFirstPayment: false
        });
        vm.prank(subscriber);
        subscriptionManager.createSubscription(params);

        // 跳过到支付时间
        ISubscriptionManager.Subscription memory subData = subscriptionManager.getSubscription(sub1);
        vm.warp(subData.nextPaymentTime);

        bytes32[] memory pending = subscriptionManager.getPendingPayments(10);
        assertEq(pending.length, 2);
    }

    function test_GetMonthlySubscriptionCost() public {
        // 创建月度订阅 10 USDC
        _createSubscription(subscriber, recipient, 10e6, false);

        // 创建每日订阅 1 USDC (约 30 USDC/月)
        address recipient2 = makeAddr("recipient2");
        ISubscriptionManager.CreateSubscriptionParams memory params = ISubscriptionManager.CreateSubscriptionParams({
            recipient: recipient2,
            token: address(usdc),
            amount: 1e6,
            billingPeriod: ISubscriptionManager.BillingPeriod.Daily,
            maxPayments: 0,
            executeFirstPayment: false
        });
        vm.prank(subscriber);
        subscriptionManager.createSubscription(params);

        uint256 monthlyCost = subscriptionManager.getMonthlySubscriptionCost(subscriber);
        // 10 + 30 = 40 USDC
        assertEq(monthlyCost, 40e6);
    }

    function test_GetRecipientStats() public {
        _createSubscription(subscriber, recipient, 10e6, false);

        // 创建另一个用户的订阅给同一个收款人
        address subscriber2 = makeAddr("subscriber2");
        usdc.mint(subscriber2, 10000e6);
        vm.prank(subscriber2);
        shieldCore.activateShield(1000e6, 100e6);

        ISubscriptionManager.CreateSubscriptionParams memory params = ISubscriptionManager.CreateSubscriptionParams({
            recipient: recipient,
            token: address(usdc),
            amount: 20e6,
            billingPeriod: ISubscriptionManager.BillingPeriod.Monthly,
            maxPayments: 12,
            executeFirstPayment: false
        });
        vm.prank(subscriber2);
        subscriptionManager.createSubscription(params);

        (uint256 activeSubscriptions, uint256 totalSubscribers, uint256 monthlyRevenue) =
            subscriptionManager.getRecipientStats(recipient);

        assertEq(activeSubscriptions, 2);
        assertEq(totalSubscribers, 2);
        assertEq(monthlyRevenue, 30e6); // 10 + 20
    }

    function test_GetPaymentHistory() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 10e6, false);

        vm.prank(subscriber);
        usdc.approve(address(subscriptionManager), type(uint256).max);

        // 跳过到支付时间并执行 3 次支付
        ISubscriptionManager.Subscription memory sub = subscriptionManager.getSubscription(subscriptionId);
        vm.warp(sub.nextPaymentTime);
        subscriptionManager.executePayment(subscriptionId);

        sub = subscriptionManager.getSubscription(subscriptionId);
        vm.warp(sub.nextPaymentTime);
        subscriptionManager.executePayment(subscriptionId);

        sub = subscriptionManager.getSubscription(subscriptionId);
        vm.warp(sub.nextPaymentTime);
        subscriptionManager.executePayment(subscriptionId);

        ISubscriptionManager.PaymentRecord[] memory history = subscriptionManager.getPaymentHistory(subscriptionId);
        assertEq(history.length, 3);
    }

    function test_CanExecutePayment() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 10e6, false);

        vm.prank(subscriber);
        usdc.approve(address(subscriptionManager), type(uint256).max);

        // 跳过到支付时间
        ISubscriptionManager.Subscription memory sub = subscriptionManager.getSubscription(subscriptionId);
        vm.warp(sub.nextPaymentTime);

        (bool canPay, string memory reason) = subscriptionManager.canExecutePayment(subscriptionId);
        assertTrue(canPay);
        assertEq(reason, "");
    }

    function test_CanExecutePayment_InsufficientBalance() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 10e6, false);

        // 移除余额
        uint256 bal = usdc.balanceOf(subscriber);
        vm.prank(subscriber);
        usdc.transfer(recipient, bal);

        vm.prank(subscriber);
        usdc.approve(address(subscriptionManager), type(uint256).max);

        // 跳过到支付时间
        ISubscriptionManager.Subscription memory sub = subscriptionManager.getSubscription(subscriptionId);
        vm.warp(sub.nextPaymentTime);

        (bool canPay, string memory reason) = subscriptionManager.canExecutePayment(subscriptionId);
        assertFalse(canPay);
        assertEq(reason, "Insufficient balance");
    }

    function test_CanExecutePayment_InsufficientAllowance() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 10e6, false);

        // 不授权

        // 跳过到支付时间
        ISubscriptionManager.Subscription memory sub = subscriptionManager.getSubscription(subscriptionId);
        vm.warp(sub.nextPaymentTime);

        (bool canPay, string memory reason) = subscriptionManager.canExecutePayment(subscriptionId);
        assertFalse(canPay);
        assertEq(reason, "Insufficient allowance");
    }

    // ==================== 管理函数测试 ====================

    function test_SetProtocolFee() public {
        subscriptionManager.setProtocolFee(100); // 1%
        assertEq(subscriptionManager.protocolFeeBps(), 100);
    }

    function test_RevertWhen_SetFeeTooHigh() public {
        vm.expectRevert("Fee too high");
        subscriptionManager.setProtocolFee(201); // > 2%
    }

    function test_SetFeeRecipient() public {
        address newRecipient = makeAddr("newFeeRecipient");
        subscriptionManager.setFeeRecipient(newRecipient);
        assertEq(subscriptionManager.feeRecipient(), newRecipient);
    }

    function test_Pause() public {
        subscriptionManager.pause();

        vm.startPrank(subscriber);
        ISubscriptionManager.CreateSubscriptionParams memory params = ISubscriptionManager.CreateSubscriptionParams({
            recipient: recipient,
            token: address(usdc),
            amount: 10e6,
            billingPeriod: ISubscriptionManager.BillingPeriod.Monthly,
            maxPayments: 12,
            executeFirstPayment: false
        });

        vm.expectRevert();
        subscriptionManager.createSubscription(params);
        vm.stopPrank();
    }

    function test_EmergencyWithdraw() public {
        usdc.mint(address(subscriptionManager), 1000e6);

        address withdrawRecipient = makeAddr("withdrawRecipient");

        // 两阶段紧急提款流程
        // 第一阶段: 提议提款
        subscriptionManager.proposeEmergencyWithdraw(address(usdc), withdrawRecipient, 1000e6);

        // 等待 48 小时时间锁
        vm.warp(block.timestamp + 48 hours);

        // 第二阶段: 执行提款
        subscriptionManager.executeEmergencyWithdraw();

        assertEq(usdc.balanceOf(withdrawRecipient), 1000e6);
    }

    // ==================== Shield 集成测试 ====================

    function test_ShieldLimitEnforced() public {
        // 创建超过单笔限额的订阅
        vm.startPrank(subscriber);
        usdc.approve(address(subscriptionManager), type(uint256).max);

        ISubscriptionManager.CreateSubscriptionParams memory params = ISubscriptionManager.CreateSubscriptionParams({
            recipient: recipient,
            token: address(usdc),
            amount: 200e6, // 超过 100e6 单笔限额
            billingPeriod: ISubscriptionManager.BillingPeriod.Monthly,
            maxPayments: 12,
            executeFirstPayment: false
        });

        bytes32 subscriptionId = subscriptionManager.createSubscription(params);
        vm.stopPrank();

        // 执行支付应该失败
        vm.expectRevert();
        subscriptionManager.executePayment(subscriptionId);
    }

    // ==================== 计费周期测试 ====================

    function test_BillingPeriodSeconds() public view {
        assertEq(subscriptionManager.getBillingPeriodSeconds(ISubscriptionManager.BillingPeriod.Daily), 86400);
        assertEq(subscriptionManager.getBillingPeriodSeconds(ISubscriptionManager.BillingPeriod.Weekly), 604800);
        assertEq(subscriptionManager.getBillingPeriodSeconds(ISubscriptionManager.BillingPeriod.Monthly), 2592000);
        assertEq(subscriptionManager.getBillingPeriodSeconds(ISubscriptionManager.BillingPeriod.Yearly), 31536000);
    }

    // ==================== 补充覆盖测试 ====================

    function test_Unpause() public {
        subscriptionManager.pause();
        subscriptionManager.unpause();

        // 验证可以创建订阅
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 50e6, false);
        assertTrue(subscriptionId != bytes32(0));
    }

    function test_GetSubscription_NonExistent() public view {
        bytes32 fakeId = keccak256("fake");
        // getSubscription 不会 revert，只返回空结构
        ISubscriptionManager.Subscription memory sub = subscriptionManager.getSubscription(fakeId);
        assertEq(sub.subscriber, address(0));
    }

    function test_RevertWhen_ExecuteCancelledSubscription() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 50e6, false);

        vm.prank(subscriber);
        subscriptionManager.cancelSubscription(subscriptionId);

        vm.expectRevert(ISubscriptionManager.SubscriptionNotActive.selector);
        subscriptionManager.executePayment(subscriptionId);
    }

    function test_RevertWhen_PauseCancelledSubscription() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 50e6, false);

        vm.startPrank(subscriber);
        subscriptionManager.cancelSubscription(subscriptionId);

        vm.expectRevert(ISubscriptionManager.SubscriptionNotActive.selector);
        subscriptionManager.pauseSubscription(subscriptionId);
        vm.stopPrank();
    }

    function test_RevertWhen_ResumeActiveSubscription() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 50e6, false);

        vm.prank(subscriber);
        vm.expectRevert("Not paused");
        subscriptionManager.resumeSubscription(subscriptionId);
    }

    function test_CancelSubscription_MultipleTimes() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 50e6, false);

        vm.startPrank(subscriber);
        subscriptionManager.cancelSubscription(subscriptionId);

        // 取消后状态已经是 Cancelled，再次取消不会改变状态
        subscriptionManager.cancelSubscription(subscriptionId);

        ISubscriptionManager.Subscription memory sub = subscriptionManager.getSubscription(subscriptionId);
        assertEq(uint(sub.status), uint(ISubscriptionManager.SubscriptionStatus.Cancelled));
        vm.stopPrank();
    }

    function test_RevertWhen_PausePausedSubscription() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 50e6, false);

        vm.startPrank(subscriber);
        subscriptionManager.pauseSubscription(subscriptionId);

        vm.expectRevert(ISubscriptionManager.SubscriptionNotActive.selector);
        subscriptionManager.pauseSubscription(subscriptionId);
        vm.stopPrank();
    }

    function test_UpdateSubscription_AfterCancel() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 50e6, false);

        vm.startPrank(subscriber);
        subscriptionManager.cancelSubscription(subscriptionId);

        // 取消后仍可更新金额，因为 updateSubscriptionAmount 不检查状态
        subscriptionManager.updateSubscriptionAmount(subscriptionId, 60e6);

        ISubscriptionManager.Subscription memory sub = subscriptionManager.getSubscription(subscriptionId);
        assertEq(sub.amount, 60e6);
        vm.stopPrank();
    }

    function test_CanExecutePayment_Cancelled() public {
        bytes32 subscriptionId = _createSubscription(subscriber, recipient, 50e6, false);

        vm.prank(subscriber);
        subscriptionManager.cancelSubscription(subscriptionId);

        (bool canExecute, string memory reason) = subscriptionManager.canExecutePayment(subscriptionId);
        assertFalse(canExecute);
        assertEq(reason, "Subscription not active");
    }

    function test_CanExecutePayment_MaxPaymentsReached() public {
        vm.startPrank(subscriber);
        usdc.approve(address(subscriptionManager), type(uint256).max);

        ISubscriptionManager.CreateSubscriptionParams memory params = ISubscriptionManager.CreateSubscriptionParams({
            recipient: recipient,
            token: address(usdc),
            amount: 50e6,
            billingPeriod: ISubscriptionManager.BillingPeriod.Daily,
            maxPayments: 1, // 只执行一次
            executeFirstPayment: true
        });

        bytes32 subscriptionId = subscriptionManager.createSubscription(params);
        vm.stopPrank();

        // 第一次已执行，检查是否可以执行更多
        (bool canExecute, string memory reason) = subscriptionManager.canExecutePayment(subscriptionId);
        assertFalse(canExecute);
        assertTrue(
            keccak256(bytes(reason)) == keccak256(bytes("Max payments reached")) ||
            keccak256(bytes(reason)) == keccak256(bytes("Payment not due yet")) ||
            keccak256(bytes(reason)) == keccak256(bytes("Subscription not active"))
        );
    }

    function test_GetUserSubscriptions() public {
        bytes32 sub1 = _createSubscription(subscriber, recipient, 50e6, false);
        vm.roll(block.number + 1);
        bytes32 sub2 = _createSubscription(subscriber, recipient, 60e6, false);

        bytes32[] memory subs = subscriptionManager.getSubscriberSubscriptions(subscriber);
        assertEq(subs.length, 2);
        assertEq(subs[0], sub1);
        assertEq(subs[1], sub2);
    }

    function test_GetRecipientSubscriptions() public {
        bytes32 sub1 = _createSubscription(subscriber, recipient, 50e6, false);
        vm.roll(block.number + 1);
        bytes32 sub2 = _createSubscription(subscriber, recipient, 60e6, false);

        bytes32[] memory subs = subscriptionManager.getRecipientSubscriptions(recipient);
        assertEq(subs.length, 2);
    }

    function test_BatchExecutePayments_AllFail() public {
        bytes32 sub1 = _createSubscription(subscriber, recipient, 50e6, false);
        vm.roll(block.number + 1);
        bytes32 sub2 = _createSubscription(subscriber, recipient, 60e6, false);

        bytes32[] memory subs = new bytes32[](2);
        subs[0] = sub1;
        subs[1] = sub2;

        // 不到支付时间，都应该失败，但不会 revert
        subscriptionManager.batchExecutePayments(subs);

        // 验证没有任何支付被执行
        ISubscriptionManager.Subscription memory s1 = subscriptionManager.getSubscription(sub1);
        ISubscriptionManager.Subscription memory s2 = subscriptionManager.getSubscription(sub2);
        assertEq(s1.paymentsCompleted, 0);
        assertEq(s2.paymentsCompleted, 0);
    }

    function test_RevertWhen_ReceiveEther() public {
        // SubscriptionManager 没有 receive 函数，不能接收 ETH
        (bool success,) = address(subscriptionManager).call{value: 1 ether}("");
        assertFalse(success);
    }

    function test_RevertWhen_ZeroToken() public {
        vm.prank(subscriber);
        vm.expectRevert("Native token not supported");

        ISubscriptionManager.CreateSubscriptionParams memory params = ISubscriptionManager.CreateSubscriptionParams({
            recipient: recipient,
            token: address(0),
            amount: 50e6,
            billingPeriod: ISubscriptionManager.BillingPeriod.Monthly,
            maxPayments: 12,
            executeFirstPayment: false
        });

        subscriptionManager.createSubscription(params);
    }

    function test_RevertWhen_ZeroMaxPayments() public {
        vm.prank(subscriber);
        // 0 maxPayments 表示无限，不应该 revert
        ISubscriptionManager.CreateSubscriptionParams memory params = ISubscriptionManager.CreateSubscriptionParams({
            recipient: recipient,
            token: address(usdc),
            amount: 50e6,
            billingPeriod: ISubscriptionManager.BillingPeriod.Monthly,
            maxPayments: 0, // 无限
            executeFirstPayment: false
        });

        bytes32 subscriptionId = subscriptionManager.createSubscription(params);
        assertTrue(subscriptionId != bytes32(0));
    }

    // ==================== 辅助函数 ====================

    function _createSubscription(
        address _subscriber,
        address _recipient,
        uint256 amount,
        bool executeFirst
    ) internal returns (bytes32) {
        vm.prank(_subscriber);
        ISubscriptionManager.CreateSubscriptionParams memory params = ISubscriptionManager.CreateSubscriptionParams({
            recipient: _recipient,
            token: address(usdc),
            amount: amount,
            billingPeriod: ISubscriptionManager.BillingPeriod.Monthly,
            maxPayments: 12,
            executeFirstPayment: executeFirst
        });

        return subscriptionManager.createSubscription(params);
    }
}
