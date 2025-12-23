// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISubscriptionManager} from "../interfaces/ISubscriptionManager.sol";
import {IShieldCore} from "../interfaces/IShieldCore.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title SubscriptionManager
 * @author Shield Protocol Team
 * @notice Web3 原生订阅支付管理合约
 * @dev 实现了订阅创建、自动支付执行和管理功能
 *
 * 核心功能:
 * 1. 创建订阅 (指定收款人、金额、周期)
 * 2. 自动执行定期支付
 * 3. 支持多种周期 (每日、每周、每月、每年)
 * 4. 与 ShieldCore 集成进行限额检查
 *
 * 使用场景:
 * - 内容创作者订阅
 * - SaaS 服务订阅
 * - DAO 会员费
 * - 定期捐赠
 */
contract SubscriptionManager is ISubscriptionManager, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============ 常量 ============

    /// @notice 各周期的秒数
    uint256 public constant SECONDS_PER_DAY = 86400;
    uint256 public constant SECONDS_PER_WEEK = 604800;
    uint256 public constant SECONDS_PER_MONTH = 2592000; // 30 天
    uint256 public constant SECONDS_PER_YEAR = 31536000; // 365 天

    /// @notice 紧急提币延迟时间 (48 小时)
    uint256 public constant EMERGENCY_WITHDRAW_DELAY = 48 hours;

    // ============ 不可变量 ============

    /// @notice Shield 核心合约
    IShieldCore public immutable shieldCore;

    // ============ 状态变量 ============

    /// @notice 订阅 ID => 订阅详情
    mapping(bytes32 => Subscription) private _subscriptions;

    /// @notice 订阅者 => 订阅 ID 数组
    mapping(address => bytes32[]) private _subscriberSubscriptions;

    /// @notice 收款人 => 订阅 ID 数组
    mapping(address => bytes32[]) private _recipientSubscriptions;

    /// @notice 订阅 ID => 支付记录数组
    mapping(bytes32 => PaymentRecord[]) private _paymentHistory;

    /// @notice 协议手续费 (基点)
    uint256 public protocolFeeBps;

    /// @notice 手续费接收地址
    address public feeRecipient;

    /// @notice 总订阅数
    uint256 public totalSubscriptions;

    /// @notice 所有订阅 ID 列表 (用于 getPendingPayments)
    bytes32[] private _allSubscriptionIds;

    /// @notice 总支付金额 (按代币)
    mapping(address => uint256) public totalPaymentsByToken;

    /// @notice 待执行的紧急提币
    struct PendingEmergencyWithdraw {
        address token;
        address to;
        uint256 amount;
        uint256 executeAfter;
        bool pending;
    }

    /// @notice 待执行的紧急提币请求
    PendingEmergencyWithdraw public pendingWithdraw;

    // ============ 构造函数 ============

    constructor(address _shieldCore) Ownable(msg.sender) {
        require(_shieldCore != address(0), "Invalid ShieldCore");
        shieldCore = IShieldCore(_shieldCore);
        feeRecipient = msg.sender;
        protocolFeeBps = 50; // 0.5% 默认手续费
    }

    // ============ 管理函数 ============

    function setProtocolFee(uint256 feeBps) external onlyOwner {
        require(feeBps <= 200, "Fee too high"); // 最高 2%
        protocolFeeBps = feeBps;
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        feeRecipient = recipient;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ 订阅管理函数 ============

    /**
     * @notice 创建订阅
     * @param params 订阅参数
     * @return subscriptionId 订阅 ID
     *
     * 设计考虑:
     * - 可选择是否立即执行第一次支付
     * - maxPayments = 0 表示无限期订阅
     * - 订阅者需要预先授权代币
     */
    function createSubscription(
        CreateSubscriptionParams calldata params
    ) external whenNotPaused nonReentrant returns (bytes32 subscriptionId) {
        // 参数验证
        if (params.recipient == address(0)) revert InvalidRecipient();
        if (params.recipient == msg.sender) revert InvalidRecipient();
        if (params.amount == 0) revert InvalidAmount();
        if (params.token == address(0)) revert("Native token not supported");

        // 生成唯一订阅 ID
        subscriptionId = keccak256(abi.encodePacked(
            msg.sender,
            params.recipient,
            params.token,
            params.amount,
            block.timestamp,
            totalSubscriptions
        ));

        // 确保 ID 唯一
        require(_subscriptions[subscriptionId].subscriber == address(0), "ID collision");

        // 计算下次支付时间
        uint256 periodSeconds = getBillingPeriodSeconds(params.billingPeriod);
        uint256 nextPaymentTime = params.executeFirstPayment
            ? block.timestamp
            : block.timestamp + periodSeconds;

        // 创建订阅
        _subscriptions[subscriptionId] = Subscription({
            subscriptionId: subscriptionId,
            subscriber: msg.sender,
            recipient: params.recipient,
            token: params.token,
            amount: params.amount,
            billingPeriod: params.billingPeriod,
            nextPaymentTime: nextPaymentTime,
            paymentsCompleted: 0,
            maxPayments: params.maxPayments,
            status: SubscriptionStatus.Active,
            createdAt: block.timestamp,
            cancelledAt: 0
        });

        // 记录索引
        _subscriberSubscriptions[msg.sender].push(subscriptionId);
        _recipientSubscriptions[params.recipient].push(subscriptionId);
        _allSubscriptionIds.push(subscriptionId);
        totalSubscriptions++;

        emit SubscriptionCreated(
            subscriptionId,
            msg.sender,
            params.recipient,
            params.token,
            params.amount,
            params.billingPeriod
        );

        // 如果需要立即执行第一次支付
        if (params.executeFirstPayment) {
            _executePayment(subscriptionId);
        }
    }

    /**
     * @notice 执行订阅支付
     * @param subscriptionId 订阅 ID
     *
     * 执行流程:
     * 1. 验证订阅状态和时间条件
     * 2. 通过 ShieldCore 检查限额
     * 3. 从订阅者账户转移代币到收款人
     * 4. 收取协议手续费
     * 5. 更新订阅状态
     */
    function executePayment(bytes32 subscriptionId) external whenNotPaused nonReentrant {
        _executePayment(subscriptionId);
    }

    /**
     * @notice 批量执行订阅支付
     * @param subscriptionIds 订阅 ID 数组
     */
    function batchExecutePayments(
        bytes32[] calldata subscriptionIds
    ) external whenNotPaused nonReentrant {
        for (uint256 i = 0; i < subscriptionIds.length; i++) {
            try this.executePaymentInternal(subscriptionIds[i]) {
                // 成功
            } catch {
                // 忽略单个失败
            }
        }
    }

    /// @notice 内部执行函数 (用于批量执行的 try-catch)
    function executePaymentInternal(bytes32 subscriptionId) external {
        require(msg.sender == address(this), "Only internal");
        _executePayment(subscriptionId);
    }

    /**
     * @notice 内部支付执行逻辑
     */
    function _executePayment(bytes32 subscriptionId) internal {
        Subscription storage sub = _subscriptions[subscriptionId];

        // 检查订阅存在
        if (sub.subscriber == address(0)) revert SubscriptionNotFound();

        // 检查状态
        if (sub.status != SubscriptionStatus.Active) revert SubscriptionNotActive();

        // 检查时间
        if (block.timestamp < sub.nextPaymentTime) {
            revert PaymentNotDue(sub.nextPaymentTime);
        }

        // 检查支付次数限制
        if (sub.maxPayments > 0 && sub.paymentsCompleted >= sub.maxPayments) {
            sub.status = SubscriptionStatus.Expired;
            emit SubscriptionExpired(subscriptionId, block.timestamp);
            revert MaxPaymentsReached();
        }

        // 通过 ShieldCore 检查限额
        // 注意: recordSpending 会在限额超出时直接 revert
        shieldCore.recordSpending(sub.subscriber, sub.token, sub.amount);

        // 计算手续费
        uint256 feeAmount = (sub.amount * protocolFeeBps) / 10000;
        uint256 recipientAmount = sub.amount - feeAmount;

        // 执行转账
        IERC20(sub.token).safeTransferFrom(sub.subscriber, sub.recipient, recipientAmount);

        // 转移手续费
        if (feeAmount > 0 && feeRecipient != address(0)) {
            IERC20(sub.token).safeTransferFrom(sub.subscriber, feeRecipient, feeAmount);
        }

        // 更新订阅状态
        sub.paymentsCompleted++;
        sub.nextPaymentTime = block.timestamp + getBillingPeriodSeconds(sub.billingPeriod);

        // 记录支付历史
        _paymentHistory[subscriptionId].push(PaymentRecord({
            subscriptionId: subscriptionId,
            amount: sub.amount,
            paymentNumber: sub.paymentsCompleted,
            timestamp: block.timestamp,
            txHash: bytes32(0) // 由外部记录
        }));

        // 更新统计
        totalPaymentsByToken[sub.token] += sub.amount;

        // 检查是否到期
        if (sub.maxPayments > 0 && sub.paymentsCompleted >= sub.maxPayments) {
            sub.status = SubscriptionStatus.Expired;
            emit SubscriptionExpired(subscriptionId, block.timestamp);
        }

        emit PaymentExecuted(
            subscriptionId,
            sub.subscriber,
            sub.recipient,
            sub.amount,
            sub.paymentsCompleted,
            block.timestamp
        );
    }

    /**
     * @notice 暂停订阅
     */
    function pauseSubscription(bytes32 subscriptionId) external {
        Subscription storage sub = _subscriptions[subscriptionId];

        if (sub.subscriber == address(0)) revert SubscriptionNotFound();
        if (sub.subscriber != msg.sender) revert NotSubscriber();
        if (sub.status != SubscriptionStatus.Active) revert SubscriptionNotActive();

        sub.status = SubscriptionStatus.Paused;

        emit SubscriptionPaused(subscriptionId, block.timestamp);
    }

    /**
     * @notice 恢复订阅
     */
    function resumeSubscription(bytes32 subscriptionId) external {
        Subscription storage sub = _subscriptions[subscriptionId];

        if (sub.subscriber == address(0)) revert SubscriptionNotFound();
        if (sub.subscriber != msg.sender) revert NotSubscriber();
        require(sub.status == SubscriptionStatus.Paused, "Not paused");

        // 检查是否已到期
        if (sub.maxPayments > 0 && sub.paymentsCompleted >= sub.maxPayments) {
            revert MaxPaymentsReached();
        }

        sub.status = SubscriptionStatus.Active;
        // 重新计算下次支付时间
        sub.nextPaymentTime = block.timestamp + getBillingPeriodSeconds(sub.billingPeriod);

        emit SubscriptionResumed(subscriptionId, block.timestamp);
    }

    /**
     * @notice 取消订阅
     */
    function cancelSubscription(bytes32 subscriptionId) external {
        Subscription storage sub = _subscriptions[subscriptionId];

        if (sub.subscriber == address(0)) revert SubscriptionNotFound();
        if (sub.subscriber != msg.sender) revert NotSubscriber();

        sub.status = SubscriptionStatus.Cancelled;
        sub.cancelledAt = block.timestamp;

        emit SubscriptionCancelled(subscriptionId, sub.paymentsCompleted, block.timestamp);
    }

    /**
     * @notice 更新订阅金额 (下次生效)
     */
    function updateSubscriptionAmount(
        bytes32 subscriptionId,
        uint256 newAmount
    ) external {
        Subscription storage sub = _subscriptions[subscriptionId];

        if (sub.subscriber == address(0)) revert SubscriptionNotFound();
        if (sub.subscriber != msg.sender) revert NotSubscriber();
        if (newAmount == 0) revert InvalidAmount();

        uint256 oldAmount = sub.amount;
        sub.amount = newAmount;

        emit SubscriptionAmountUpdated(subscriptionId, oldAmount, newAmount);
    }

    // ============ 视图函数 ============

    /**
     * @notice 获取订阅详情
     */
    function getSubscription(
        bytes32 subscriptionId
    ) external view returns (Subscription memory) {
        return _subscriptions[subscriptionId];
    }

    /**
     * @notice 获取用户作为订阅者的所有订阅
     */
    function getSubscriberSubscriptions(
        address subscriber
    ) external view returns (bytes32[] memory) {
        return _subscriberSubscriptions[subscriber];
    }

    /**
     * @notice 获取用户作为收款人的所有订阅
     */
    function getRecipientSubscriptions(
        address recipient
    ) external view returns (bytes32[] memory) {
        return _recipientSubscriptions[recipient];
    }

    /**
     * @notice 获取待执行支付的订阅
     * @param limit 返回数量限制
     * @return subscriptionIds 待执行的订阅 ID 数组
     */
    function getPendingPayments(
        uint256 limit
    ) external view returns (bytes32[] memory subscriptionIds) {
        uint256 count = 0;
        uint256 maxLen = limit > _allSubscriptionIds.length ? _allSubscriptionIds.length : limit;
        bytes32[] memory temp = new bytes32[](maxLen);

        for (uint256 i = 0; i < _allSubscriptionIds.length && count < maxLen; i++) {
            bytes32 sid = _allSubscriptionIds[i];
            Subscription memory sub = _subscriptions[sid];

            // 检查订阅是否可执行支付
            if (
                sub.status == SubscriptionStatus.Active &&
                block.timestamp >= sub.nextPaymentTime &&
                (sub.maxPayments == 0 || sub.paymentsCompleted < sub.maxPayments)
            ) {
                temp[count] = sid;
                count++;
            }
        }

        // 创建精确大小的返回数组
        subscriptionIds = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            subscriptionIds[i] = temp[i];
        }
    }

    /**
     * @notice 检查订阅是否可执行支付
     */
    function canExecutePayment(
        bytes32 subscriptionId
    ) external view returns (bool canPay, string memory reason) {
        Subscription memory sub = _subscriptions[subscriptionId];

        if (sub.subscriber == address(0)) {
            return (false, "Subscription not found");
        }

        if (sub.status != SubscriptionStatus.Active) {
            return (false, "Subscription not active");
        }

        if (block.timestamp < sub.nextPaymentTime) {
            return (false, "Payment not due");
        }

        if (sub.maxPayments > 0 && sub.paymentsCompleted >= sub.maxPayments) {
            return (false, "Max payments reached");
        }

        // 检查 Shield 限额
        (bool allowed, string memory shieldReason) = shieldCore.checkSpendingAllowed(
            sub.subscriber,
            sub.token,
            sub.amount
        );
        if (!allowed) {
            return (false, shieldReason);
        }

        // 检查余额
        uint256 balance = IERC20(sub.token).balanceOf(sub.subscriber);
        if (balance < sub.amount) {
            return (false, "Insufficient balance");
        }

        // 检查授权
        uint256 allowance = IERC20(sub.token).allowance(sub.subscriber, address(this));
        if (allowance < sub.amount) {
            return (false, "Insufficient allowance");
        }

        return (true, "");
    }

    /**
     * @notice 获取订阅的支付历史
     */
    function getPaymentHistory(
        bytes32 subscriptionId
    ) external view returns (PaymentRecord[] memory) {
        return _paymentHistory[subscriptionId];
    }

    /**
     * @notice 计算用户的月度订阅支出
     */
    function getMonthlySubscriptionCost(
        address subscriber
    ) external view returns (uint256 monthlyTotal) {
        bytes32[] memory subscriptionIds = _subscriberSubscriptions[subscriber];

        for (uint256 i = 0; i < subscriptionIds.length; i++) {
            Subscription memory sub = _subscriptions[subscriptionIds[i]];

            if (sub.status != SubscriptionStatus.Active) continue;

            // 转换为月度成本
            uint256 periodSeconds = getBillingPeriodSeconds(sub.billingPeriod);
            uint256 monthlyAmount = (sub.amount * SECONDS_PER_MONTH) / periodSeconds;
            monthlyTotal += monthlyAmount;
        }
    }

    /**
     * @notice 获取周期的秒数
     */
    function getBillingPeriodSeconds(BillingPeriod period) public pure returns (uint256) {
        if (period == BillingPeriod.Daily) return SECONDS_PER_DAY;
        if (period == BillingPeriod.Weekly) return SECONDS_PER_WEEK;
        if (period == BillingPeriod.Monthly) return SECONDS_PER_MONTH;
        if (period == BillingPeriod.Yearly) return SECONDS_PER_YEAR;
        revert InvalidBillingPeriod();
    }

    /**
     * @notice 获取收款人的统计数据
     */
    function getRecipientStats(address recipient) external view returns (
        uint256 activeSubscriptions,
        uint256 totalSubscribers,
        uint256 monthlyRevenue
    ) {
        bytes32[] memory subscriptionIds = _recipientSubscriptions[recipient];
        totalSubscribers = subscriptionIds.length;

        for (uint256 i = 0; i < subscriptionIds.length; i++) {
            Subscription memory sub = _subscriptions[subscriptionIds[i]];

            if (sub.status == SubscriptionStatus.Active) {
                activeSubscriptions++;
                uint256 periodSeconds = getBillingPeriodSeconds(sub.billingPeriod);
                monthlyRevenue += (sub.amount * SECONDS_PER_MONTH) / periodSeconds;
            }
        }
    }

    // ============ 紧急函数 ============

    /**
     * @notice 提议紧急提取代币
     * @param token 代币地址
     * @param to 接收地址
     * @param amount 金额
     *
     * 安全改进: 添加 48 小时时间锁
     */
    function proposeEmergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        
        uint256 executeAfter = block.timestamp + EMERGENCY_WITHDRAW_DELAY;
        
        pendingWithdraw = PendingEmergencyWithdraw({
            token: token,
            to: to,
            amount: amount,
            executeAfter: executeAfter,
            pending: true
        });
        
        emit EmergencyWithdrawProposed(token, to, amount, executeAfter);
    }

    /**
     * @notice 执行紧急提取
     *
     * 要求: 必须等待时间锁到期
     */
    function executeEmergencyWithdraw() external onlyOwner {
        PendingEmergencyWithdraw memory withdraw = pendingWithdraw;
        
        require(withdraw.pending, "No pending withdrawal");
        require(block.timestamp >= withdraw.executeAfter, "Timelock not expired");
        
        IERC20(withdraw.token).safeTransfer(withdraw.to, withdraw.amount);
        
        delete pendingWithdraw;
        
        emit EmergencyWithdrawExecuted(withdraw.token, withdraw.to, withdraw.amount);
    }

    /**
     * @notice 取消紧急提取
     */
    function cancelEmergencyWithdraw() external onlyOwner {
        require(pendingWithdraw.pending, "No pending withdrawal");
        
        delete pendingWithdraw;
        
        emit EmergencyWithdrawCancelled();
    }

    // ============ 事件 ============

    event EmergencyWithdrawProposed(
        address indexed token,
        address indexed to,
        uint256 amount,
        uint256 executeAfter
    );

    event EmergencyWithdrawExecuted(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    event EmergencyWithdrawCancelled();
}
