// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ISubscriptionManager
 * @notice Web3 订阅支付管理接口
 * @dev 定义了订阅创建、支付执行和管理功能
 */
interface ISubscriptionManager {
    // ============ 枚举 ============

    /// @notice 订阅状态
    enum SubscriptionStatus {
        Active,      // 活跃中
        Paused,      // 已暂停
        Cancelled,   // 已取消
        Expired      // 已过期
    }

    /// @notice 订阅周期类型
    enum BillingPeriod {
        Daily,       // 每日
        Weekly,      // 每周
        Monthly,     // 每月
        Yearly       // 每年
    }

    // ============ 结构体 ============

    /// @notice 订阅配置
    struct Subscription {
        bytes32 subscriptionId;        // 订阅 ID
        address subscriber;            // 订阅者
        address recipient;             // 收款人
        address token;                 // 支付代币
        uint256 amount;                // 支付金额
        BillingPeriod billingPeriod;   // 支付周期
        uint256 nextPaymentTime;       // 下次支付时间
        uint256 paymentsCompleted;     // 已完成支付次数
        uint256 maxPayments;           // 最大支付次数 (0 = 无限)
        SubscriptionStatus status;     // 订阅状态
        uint256 createdAt;             // 创建时间
        uint256 cancelledAt;           // 取消时间 (如果已取消)
    }

    /// @notice 创建订阅的参数
    struct CreateSubscriptionParams {
        address recipient;
        address token;
        uint256 amount;
        BillingPeriod billingPeriod;
        uint256 maxPayments;           // 0 = 无限
        bool executeFirstPayment;      // 是否立即执行第一次支付
    }

    /// @notice 支付记录
    struct PaymentRecord {
        bytes32 subscriptionId;
        uint256 amount;
        uint256 paymentNumber;
        uint256 timestamp;
        bytes32 txHash;
    }

    // ============ 事件 ============

    /// @notice 订阅创建事件
    event SubscriptionCreated(
        bytes32 indexed subscriptionId,
        address indexed subscriber,
        address indexed recipient,
        address token,
        uint256 amount,
        BillingPeriod billingPeriod
    );

    /// @notice 支付执行事件
    event PaymentExecuted(
        bytes32 indexed subscriptionId,
        address indexed subscriber,
        address indexed recipient,
        uint256 amount,
        uint256 paymentNumber,
        uint256 timestamp
    );

    /// @notice 订阅暂停事件
    event SubscriptionPaused(bytes32 indexed subscriptionId, uint256 timestamp);

    /// @notice 订阅恢复事件
    event SubscriptionResumed(bytes32 indexed subscriptionId, uint256 timestamp);

    /// @notice 订阅取消事件
    event SubscriptionCancelled(
        bytes32 indexed subscriptionId,
        uint256 paymentsCompleted,
        uint256 timestamp
    );

    /// @notice 订阅到期事件
    event SubscriptionExpired(bytes32 indexed subscriptionId, uint256 timestamp);

    /// @notice 订阅金额更新事件
    event SubscriptionAmountUpdated(
        bytes32 indexed subscriptionId,
        uint256 oldAmount,
        uint256 newAmount
    );

    // ============ 错误 ============

    error SubscriptionNotFound();
    error SubscriptionNotActive();
    error NotSubscriber();
    error PaymentNotDue(uint256 nextPaymentTime);
    error MaxPaymentsReached();
    error InvalidRecipient();
    error InvalidAmount();
    error InvalidBillingPeriod();
    // 注意: ShieldCore 的限额错误 (ExceedsDailyLimit, ExceedsSingleTxLimit) 会直接冒泡

    // ============ 函数 ============

    /// @notice 创建订阅
    /// @param params 订阅参数
    /// @return subscriptionId 订阅 ID
    function createSubscription(
        CreateSubscriptionParams calldata params
    ) external returns (bytes32 subscriptionId);

    /// @notice 执行订阅支付
    /// @param subscriptionId 订阅 ID
    function executePayment(bytes32 subscriptionId) external;

    /// @notice 批量执行订阅支付
    /// @param subscriptionIds 订阅 ID 数组
    function batchExecutePayments(bytes32[] calldata subscriptionIds) external;

    /// @notice 暂停订阅
    /// @param subscriptionId 订阅 ID
    function pauseSubscription(bytes32 subscriptionId) external;

    /// @notice 恢复订阅
    /// @param subscriptionId 订阅 ID
    function resumeSubscription(bytes32 subscriptionId) external;

    /// @notice 取消订阅
    /// @param subscriptionId 订阅 ID
    function cancelSubscription(bytes32 subscriptionId) external;

    /// @notice 更新订阅金额 (下次生效)
    /// @param subscriptionId 订阅 ID
    /// @param newAmount 新金额
    function updateSubscriptionAmount(bytes32 subscriptionId, uint256 newAmount) external;

    /// @notice 获取订阅详情
    /// @param subscriptionId 订阅 ID
    /// @return subscription 订阅详情
    function getSubscription(
        bytes32 subscriptionId
    ) external view returns (Subscription memory subscription);

    /// @notice 获取用户作为订阅者的所有订阅
    /// @param subscriber 订阅者地址
    /// @return subscriptionIds 订阅 ID 数组
    function getSubscriberSubscriptions(
        address subscriber
    ) external view returns (bytes32[] memory subscriptionIds);

    /// @notice 获取用户作为收款人的所有订阅
    /// @param recipient 收款人地址
    /// @return subscriptionIds 订阅 ID 数组
    function getRecipientSubscriptions(
        address recipient
    ) external view returns (bytes32[] memory subscriptionIds);

    /// @notice 获取待执行支付的订阅
    /// @param limit 返回数量限制
    /// @return subscriptionIds 待执行的订阅 ID 数组
    function getPendingPayments(
        uint256 limit
    ) external view returns (bytes32[] memory subscriptionIds);

    /// @notice 检查订阅是否可执行支付
    /// @param subscriptionId 订阅 ID
    /// @return canPay 是否可支付
    /// @return reason 如果不可支付，返回原因
    function canExecutePayment(
        bytes32 subscriptionId
    ) external view returns (bool canPay, string memory reason);

    /// @notice 获取订阅的支付历史
    /// @param subscriptionId 订阅 ID
    /// @return records 支付记录数组
    function getPaymentHistory(
        bytes32 subscriptionId
    ) external view returns (PaymentRecord[] memory records);

    /// @notice 计算用户的月度订阅支出
    /// @param subscriber 订阅者地址
    /// @return monthlyTotal 月度总支出
    function getMonthlySubscriptionCost(
        address subscriber
    ) external view returns (uint256 monthlyTotal);

    /// @notice 获取周期的秒数
    /// @param period 周期类型
    /// @return seconds 秒数
    function getBillingPeriodSeconds(BillingPeriod period) external pure returns (uint256);
}
