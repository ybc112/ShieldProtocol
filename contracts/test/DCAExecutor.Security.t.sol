// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {DCAExecutor} from "../src/strategies/DCAExecutor.sol";
import {ShieldCore} from "../src/core/ShieldCore.sol";
import {IDCAExecutor} from "../src/interfaces/IDCAExecutor.sol";
import {IShieldCore} from "../src/interfaces/IShieldCore.sol";
import {MockERC20, MockSwapRouter, MockWETH} from "./mocks/Mocks.sol";

/**
 * @title DCAExecutorSecurityTest
 * @notice 测试 DCAExecutor 的安全改进功能
 * 
 * 测试内容:
 * 1. 价格异常检测 (20% 偏差自动暂停)
 * 2. 紧急提币时间锁 (48小时)
 * 3. 批量查询分页功能
 */
contract DCAExecutorSecurityTest is Test {
    DCAExecutor public dcaExecutor;
    ShieldCore public shieldCore;
    MockSwapRouter public swapRouter;
    MockERC20 public usdc;
    MockERC20 public weth;

    address public owner;
    address public user1;
    address public keeper;

    // 事件
    event StrategyAutoPaused(
        bytes32 indexed strategyId,
        string reason,
        uint256 avgPrice,
        uint256 currentPrice,
        uint256 deviation
    );
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

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        keeper = makeAddr("keeper");

        // 部署合约
        shieldCore = new ShieldCore();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped ETH", "WETH", 18);
        swapRouter = new MockSwapRouter();

        dcaExecutor = new DCAExecutor(
            address(shieldCore),
            address(swapRouter),
            address(weth)
        );

        // 授权 DCAExecutor 作为执行器
        shieldCore.addAuthorizedExecutor(address(dcaExecutor));

        // 设置 swap 汇率: 1 USDC = 0.0004 ETH (2500 USDC/ETH)
        swapRouter.setExchangeRate(address(usdc), address(weth), 0.0004 ether);

        // 给用户分配代币
        usdc.mint(user1, 10000e6);
        vm.prank(user1);
        usdc.approve(address(dcaExecutor), type(uint256).max);

        // 用户激活 Shield
        vm.prank(user1);
        shieldCore.activateShield(1000e6, 100e6);
    }

    // ==================== 价格异常检测测试 ====================

    function test_PriceAnomalyDetection_NormalExecution() public {
        // 创建 DCA 策略
        vm.prank(user1);
        bytes32 strategyId = dcaExecutor.createStrategy(
            IDCAExecutor.CreateStrategyParams({
                sourceToken: address(usdc),
                targetToken: address(weth),
                amountPerExecution: 20e6,
                minAmountOut: 0,
                intervalSeconds: 1 days,
                totalExecutions: 5,
                poolFee: 3000
            })
        );

        // 第一次执行（建立基准价格）
        vm.prank(keeper);
        dcaExecutor.executeDCA(strategyId);

        // 检查价格已记录
        uint256 firstPrice = dcaExecutor.lastExecutionPrice(strategyId);
        assertGt(firstPrice, 0, "Price should be recorded");

        uint256 avgPrice = dcaExecutor.rollingAvgPrice(strategyId);
        assertEq(avgPrice, firstPrice, "First execution should set avg price");
    }

    function test_PriceAnomalyDetection_NormalPriceChange() public {
        // 创建策略
        vm.prank(user1);
        bytes32 strategyId = dcaExecutor.createStrategy(
            IDCAExecutor.CreateStrategyParams({
                sourceToken: address(usdc),
                targetToken: address(weth),
                amountPerExecution: 20e6,
                minAmountOut: 0,
                intervalSeconds: 1 days,
                totalExecutions: 5,
                poolFee: 3000
            })
        );

        // 第一次执行
        vm.prank(keeper);
        dcaExecutor.executeDCA(strategyId);

        // 价格变化 10% (在 20% 阈值内)
        vm.warp(block.timestamp + 1 days);
        swapRouter.setExchangeRate(address(usdc), address(weth), 0.00044 ether); // +10%

        // 第二次执行应该成功
        vm.prank(keeper);
        dcaExecutor.executeDCA(strategyId);

        // 检查策略仍然活跃
        IDCAExecutor.DCAStrategy memory strategy = dcaExecutor.getStrategy(strategyId);
        assertEq(uint(strategy.status), uint(IDCAExecutor.StrategyStatus.Active), "Should remain active");
    }

    function test_PriceAnomalyDetection_LargePriceDrop() public {
        // 创建策略
        vm.prank(user1);
        bytes32 strategyId = dcaExecutor.createStrategy(
            IDCAExecutor.CreateStrategyParams({
                sourceToken: address(usdc),
                targetToken: address(weth),
                amountPerExecution: 20e6,
                minAmountOut: 0,
                intervalSeconds: 1 days,
                totalExecutions: 5,
                poolFee: 3000
            })
        );

        // 第一次执行
        vm.prank(keeper);
        dcaExecutor.executeDCA(strategyId);

        uint256 firstAvgPrice = dcaExecutor.rollingAvgPrice(strategyId);

        // 模拟价格暴跌 50% (超过 20% 阈值)
        vm.warp(block.timestamp + 1 days);
        swapRouter.setExchangeRate(address(usdc), address(weth), 0.0008 ether); // 价格翻倍 = 价值减半

        // 第二次执行会完成但策略会被暂停
        vm.prank(keeper);
        dcaExecutor.executeDCA(strategyId);

        // 检查策略已被暂停
        IDCAExecutor.DCAStrategy memory strategy = dcaExecutor.getStrategy(strategyId);
        assertEq(uint(strategy.status), uint(IDCAExecutor.StrategyStatus.Paused), "Should be paused");

        // 验证执行次数增加了（交易完成了）
        assertEq(strategy.executionsCompleted, 2, "Should have completed 2 executions");
    }

    function test_PriceAnomalyDetection_LargePriceSpike() public {
        // 创建策略
        vm.prank(user1);
        bytes32 strategyId = dcaExecutor.createStrategy(
            IDCAExecutor.CreateStrategyParams({
                sourceToken: address(usdc),
                targetToken: address(weth),
                amountPerExecution: 20e6,
                minAmountOut: 0,
                intervalSeconds: 1 days,
                totalExecutions: 5,
                poolFee: 3000
            })
        );

        // 第一次执行
        vm.prank(keeper);
        dcaExecutor.executeDCA(strategyId);

        // 模拟价格暴涨 50% (超过 20% 阈值)
        vm.warp(block.timestamp + 1 days);
        swapRouter.setExchangeRate(address(usdc), address(weth), 0.0002 ether); // 价格减半 = 价值翻倍

        // 第二次执行会完成但策略会被暂停
        vm.prank(keeper);
        dcaExecutor.executeDCA(strategyId);

        // 检查策略已被暂停
        IDCAExecutor.DCAStrategy memory strategy = dcaExecutor.getStrategy(strategyId);
        assertEq(uint(strategy.status), uint(IDCAExecutor.StrategyStatus.Paused), "Should be paused");

        // 验证执行次数增加了（交易完成了）
        assertEq(strategy.executionsCompleted, 2, "Should have completed 2 executions");
    }

    function test_PriceAnomalyDetection_RollingAverage() public {
        // 创建策略
        vm.prank(user1);
        bytes32 strategyId = dcaExecutor.createStrategy(
            IDCAExecutor.CreateStrategyParams({
                sourceToken: address(usdc),
                targetToken: address(weth),
                amountPerExecution: 20e6,
                minAmountOut: 0,
                intervalSeconds: 1 days,
                totalExecutions: 10,
                poolFee: 3000
            })
        );

        // 执行多次，检查滚动平均价格
        for (uint i = 0; i < 5; i++) {
            vm.warp(block.timestamp + 1 days);
            
            // 轻微价格波动 (±5%)
            if (i % 2 == 0) {
                swapRouter.setExchangeRate(address(usdc), address(weth), 0.00042 ether);
            } else {
                swapRouter.setExchangeRate(address(usdc), address(weth), 0.00038 ether);
            }
            
            vm.prank(keeper);
            dcaExecutor.executeDCA(strategyId);
        }

        // 滚动平均应该平滑价格波动
        uint256 avgPrice = dcaExecutor.rollingAvgPrice(strategyId);
        assertGt(avgPrice, 0, "Average price should be positive");
    }

    // ==================== 紧急提币时间锁测试 ====================

    function test_EmergencyWithdraw_ProposalCreated() public {
        // Owner 提议紧急提币
        vm.expectEmit(true, true, false, false);
        emit EmergencyWithdrawProposed(
            address(usdc),
            owner,
            1000e6,
            block.timestamp + 48 hours
        );
        dcaExecutor.proposeEmergencyWithdraw(address(usdc), owner, 1000e6);

        // 检查提议已记录
        (
            address token,
            address to,
            uint256 amount,
            uint256 executeAfter,
            bool pending
        ) = dcaExecutor.pendingWithdraw();

        assertEq(token, address(usdc), "Token should match");
        assertEq(to, owner, "Recipient should match");
        assertEq(amount, 1000e6, "Amount should match");
        assertEq(executeAfter, block.timestamp + 48 hours, "Execute time should be 48h later");
        assertTrue(pending, "Should be pending");
    }

    function test_EmergencyWithdraw_CannotExecuteImmediately() public {
        // 提议提币
        dcaExecutor.proposeEmergencyWithdraw(address(usdc), owner, 1000e6);

        // 尝试立即执行（应该失败）
        vm.expectRevert("Timelock not expired");
        dcaExecutor.executeEmergencyWithdraw();
    }

    function test_EmergencyWithdraw_ExecuteAfterDelay() public {
        // 给合约一些代币（模拟卡住的资金）
        usdc.mint(address(dcaExecutor), 1000e6);

        uint256 ownerBalanceBefore = usdc.balanceOf(owner);

        // 提议提币
        dcaExecutor.proposeEmergencyWithdraw(address(usdc), owner, 1000e6);

        // 快进 48 小时
        vm.warp(block.timestamp + 48 hours);

        // 执行提币
        vm.expectEmit(true, true, false, false);
        emit EmergencyWithdrawExecuted(address(usdc), owner, 1000e6);
        dcaExecutor.executeEmergencyWithdraw();

        // 验证代币已转移
        uint256 ownerBalanceAfter = usdc.balanceOf(owner);
        assertEq(ownerBalanceAfter - ownerBalanceBefore, 1000e6, "Should receive tokens");

        // 验证待执行记录已删除
        (, , , , bool pending) = dcaExecutor.pendingWithdraw();
        assertFalse(pending, "Should no longer be pending");
    }

    function test_EmergencyWithdraw_CanCancel() public {
        // 提议提币
        dcaExecutor.proposeEmergencyWithdraw(address(usdc), owner, 1000e6);

        // 取消提币
        dcaExecutor.cancelEmergencyWithdraw();

        // 验证已取消
        (, , , , bool pending) = dcaExecutor.pendingWithdraw();
        assertFalse(pending, "Should be cancelled");

        // 尝试执行应该失败
        vm.warp(block.timestamp + 48 hours);
        vm.expectRevert("No pending withdrawal");
        dcaExecutor.executeEmergencyWithdraw();
    }

    function test_EmergencyWithdraw_OnlyOwnerCanPropose() public {
        vm.prank(user1);
        vm.expectRevert();
        dcaExecutor.proposeEmergencyWithdraw(address(usdc), user1, 1000e6);
    }

    function test_EmergencyWithdraw_ValidatesParameters() public {
        // 无效的 token
        vm.expectRevert("Invalid token");
        dcaExecutor.proposeEmergencyWithdraw(address(0), owner, 1000e6);

        // 无效的接收地址
        vm.expectRevert("Invalid recipient");
        dcaExecutor.proposeEmergencyWithdraw(address(usdc), address(0), 1000e6);

        // 无效的金额
        vm.expectRevert("Invalid amount");
        dcaExecutor.proposeEmergencyWithdraw(address(usdc), owner, 0);
    }

    // ==================== 批量查询分页测试 ====================

    function test_GetPendingStrategies_Pagination() public {
        // 创建多个策略
        bytes32[] memory strategyIds = new bytes32[](10);
        for (uint i = 0; i < 10; i++) {
            // 推进区块号避免 Strategy ID 冲突
            vm.roll(block.number + 1);
            vm.prank(user1);
            strategyIds[i] = dcaExecutor.createStrategy(
                IDCAExecutor.CreateStrategyParams({
                    sourceToken: address(usdc),
                    targetToken: address(weth),
                    amountPerExecution: 20e6,
                    minAmountOut: 0,
                    intervalSeconds: 1 days,
                    totalExecutions: 5,
                    poolFee: 3000
                })
            );
        }

        // 第一页（0-5）
        (bytes32[] memory page1, uint256 nextIndex1) = dcaExecutor.getPendingStrategies(0, 5);
        assertEq(page1.length, 5, "First page should have 5 strategies");
        assertEq(nextIndex1, 5, "Next index should be 5");

        // 第二页（5-10）
        (bytes32[] memory page2, uint256 nextIndex2) = dcaExecutor.getPendingStrategies(5, 5);
        assertEq(page2.length, 5, "Second page should have 5 strategies");
        // 当到达末尾时 nextIndex 返回 0
        assertEq(nextIndex2, 0, "Next index should be 0 (end of list)");

        // 第三页（已到末尾）
        (bytes32[] memory page3, uint256 nextIndex3) = dcaExecutor.getPendingStrategies(10, 5);
        assertEq(page3.length, 0, "Third page should be empty");
        assertEq(nextIndex3, 0, "Next index should be 0 (end)");
    }

    function test_GetPendingStrategies_FilterInactive() public {
        // 创建 5 个策略
        bytes32[] memory strategyIds = new bytes32[](5);
        for (uint i = 0; i < 5; i++) {
            // 推进区块号避免 Strategy ID 冲突
            vm.roll(block.number + 1);
            vm.prank(user1);
            strategyIds[i] = dcaExecutor.createStrategy(
                IDCAExecutor.CreateStrategyParams({
                    sourceToken: address(usdc),
                    targetToken: address(weth),
                    amountPerExecution: 20e6,
                    minAmountOut: 0,
                    intervalSeconds: 1 days,
                    totalExecutions: 2,
                    poolFee: 3000
                })
            );
        }

        // 暂停第 2 和第 4 个策略
        vm.prank(user1);
        dcaExecutor.pauseStrategy(strategyIds[1]);
        vm.prank(user1);
        dcaExecutor.pauseStrategy(strategyIds[3]);

        // 获取待执行策略（应该只有 3 个）
        (bytes32[] memory pending, ) = dcaExecutor.getPendingStrategies(0, 10);
        assertEq(pending.length, 3, "Should only return active strategies");
    }

    // ==================== 集成安全测试 ====================

    function test_SecurityStack_PriceCheckAndTimelock() public {
        // 测试价格异常检测和紧急提币时间锁同时工作

        // 创建策略
        vm.prank(user1);
        bytes32 strategyId = dcaExecutor.createStrategy(
            IDCAExecutor.CreateStrategyParams({
                sourceToken: address(usdc),
                targetToken: address(weth),
                amountPerExecution: 20e6,
                minAmountOut: 0,
                intervalSeconds: 1 days,
                totalExecutions: 5,
                poolFee: 3000
            })
        );

        // 第一次执行
        vm.prank(keeper);
        dcaExecutor.executeDCA(strategyId);

        // 模拟价格崩溃，策略被自动暂停
        vm.warp(block.timestamp + 1 days);
        swapRouter.setExchangeRate(address(usdc), address(weth), 0.0008 ether);

        // 第二次执行会完成但策略会被暂停
        vm.prank(keeper);
        dcaExecutor.executeDCA(strategyId);

        // 验证策略已被暂停
        IDCAExecutor.DCAStrategy memory strategy = dcaExecutor.getStrategy(strategyId);
        assertEq(uint(strategy.status), uint(IDCAExecutor.StrategyStatus.Paused), "Should be paused after price anomaly");

        // 此时可能有一些代币卡在合约中（真实场景）
        // Owner 想要紧急提取，但需要等待 48 小时
        usdc.mint(address(dcaExecutor), 100e6);
        dcaExecutor.proposeEmergencyWithdraw(address(usdc), owner, 100e6);

        // 立即执行会失败
        vm.expectRevert("Timelock not expired");
        dcaExecutor.executeEmergencyWithdraw();

        // 等待 48 小时后才能执行
        vm.warp(block.timestamp + 48 hours);
        dcaExecutor.executeEmergencyWithdraw();
    }
}

