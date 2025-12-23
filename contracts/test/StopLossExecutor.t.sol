// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ShieldCore} from "../src/core/ShieldCore.sol";
import {StopLossExecutor} from "../src/strategies/StopLossExecutor.sol";
import {IStopLossExecutor} from "../src/interfaces/IStopLossExecutor.sol";
import {MockERC20, MockSwapRouter, MockPriceOracle} from "./mocks/Mocks.sol";

/**
 * @title StopLossExecutorTest
 * @notice StopLossExecutor 合约完整测试套件
 */
contract StopLossExecutorTest is Test {
    ShieldCore public shieldCore;
    StopLossExecutor public stopLossExecutor;
    MockSwapRouter public swapRouter;
    MockPriceOracle public priceOracle;
    MockERC20 public usdc;
    MockERC20 public weth;

    address public owner;
    address public user1;
    address public user2;

    // 价格常量
    uint256 constant WETH_PRICE = 2500e18; // $2500
    uint256 constant USDC_PRICE = 1e18;    // $1

    // 事件定义
    event StrategyCreated(
        bytes32 indexed strategyId,
        address indexed user,
        address tokenToSell,
        address tokenToReceive,
        uint256 amount,
        IStopLossExecutor.StopLossType stopLossType,
        uint256 triggerValue
    );
    event StopLossTriggered(
        bytes32 indexed strategyId,
        address indexed user,
        uint256 currentPrice,
        uint256 triggerPrice,
        uint256 timestamp
    );
    event StopLossExecuted(
        bytes32 indexed strategyId,
        address indexed user,
        uint256 amountSold,
        uint256 amountReceived,
        uint256 executionPrice,
        uint256 timestamp
    );
    event HighestPriceUpdated(
        bytes32 indexed strategyId,
        uint256 oldHighest,
        uint256 newHighest
    );
    event StrategyPaused(bytes32 indexed strategyId, uint256 timestamp);
    event StrategyResumed(bytes32 indexed strategyId, uint256 timestamp);
    event StrategyCancelled(bytes32 indexed strategyId, uint256 timestamp);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // 部署 Mock 合约
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        swapRouter = new MockSwapRouter();
        priceOracle = new MockPriceOracle();

        // 设置初始价格
        priceOracle.setPrice(address(usdc), USDC_PRICE);
        priceOracle.setPrice(address(weth), WETH_PRICE);

        // 部署核心合约
        shieldCore = new ShieldCore();

        // 部署止损执行器
        stopLossExecutor = new StopLossExecutor(
            address(shieldCore),
            address(swapRouter),
            address(priceOracle)
        );

        // 配置授权
        shieldCore.addAuthorizedExecutor(address(stopLossExecutor));

        // 给用户铸造测试代币
        weth.mint(user1, 10e18);  // 10 WETH
        weth.mint(user2, 10e18);
        usdc.mint(user1, 10000e6); // 10000 USDC

        // 给 SwapRouter 一些代币用于交换
        usdc.mint(address(swapRouter), 1000000e6);
        weth.mint(address(swapRouter), 1000e18);

        // 用户激活 Shield (设置足够高的限额以支持 18 位小数的代币)
        vm.prank(user1);
        shieldCore.activateShield(100000e18, 50000e18);

        vm.prank(user2);
        shieldCore.activateShield(100000e18, 50000e18);
    }

    // ==================== 固定价格止损测试 ====================

    function test_CreateStrategy_FixedPrice_Success() public {
        vm.startPrank(user1);

        IStopLossExecutor.CreateStrategyParams memory params = IStopLossExecutor.CreateStrategyParams({
            tokenToSell: address(weth),
            tokenToReceive: address(usdc),
            amount: 1e18, // 1 WETH
            stopLossType: IStopLossExecutor.StopLossType.FixedPrice,
            triggerValue: 2000e18, // 触发价格 $2000
            trailingDistance: 0,
            minAmountOut: 0,
            poolFee: 3000
        });

        bytes32 strategyId = stopLossExecutor.createStrategy(params);

        vm.stopPrank();

        // 验证策略
        IStopLossExecutor.StopLossStrategy memory strategy = stopLossExecutor.getStrategy(strategyId);
        assertEq(strategy.user, user1);
        assertEq(strategy.tokenToSell, address(weth));
        assertEq(strategy.tokenToReceive, address(usdc));
        assertEq(strategy.amount, 1e18);
        assertEq(uint(strategy.stopLossType), uint(IStopLossExecutor.StopLossType.FixedPrice));
        assertEq(strategy.triggerPrice, 2000e18);
        assertEq(uint(strategy.status), uint(IStopLossExecutor.StrategyStatus.Active));
    }

    function test_FixedPrice_ShouldNotTrigger_AbovePrice() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        (bool triggered, uint256 currentPrice) = stopLossExecutor.shouldTrigger(strategyId);
        assertFalse(triggered);
        assertEq(currentPrice, WETH_PRICE); // $2500 > $2000
    }

    function test_FixedPrice_ShouldTrigger_BelowPrice() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        // 模拟价格下跌到 $1900
        priceOracle.setPrice(address(weth), 1900e18);

        (bool triggered, uint256 currentPrice) = stopLossExecutor.shouldTrigger(strategyId);
        assertTrue(triggered);
        assertEq(currentPrice, 1900e18);
    }

    function test_FixedPrice_Execute_Success() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        // 用户授权
        vm.prank(user1);
        weth.approve(address(stopLossExecutor), type(uint256).max);

        // 模拟价格下跌
        priceOracle.setPrice(address(weth), 1900e18);

        // 执行止损
        bool executed = stopLossExecutor.checkAndExecute(strategyId);
        assertTrue(executed);

        // 验证状态
        IStopLossExecutor.StopLossStrategy memory strategy = stopLossExecutor.getStrategy(strategyId);
        assertEq(uint(strategy.status), uint(IStopLossExecutor.StrategyStatus.Triggered));
        assertTrue(strategy.triggeredAt > 0);
    }

    // ==================== 百分比止损测试 ====================

    function test_CreateStrategy_Percentage_Success() public {
        vm.startPrank(user1);

        IStopLossExecutor.CreateStrategyParams memory params = IStopLossExecutor.CreateStrategyParams({
            tokenToSell: address(weth),
            tokenToReceive: address(usdc),
            amount: 1e18,
            stopLossType: IStopLossExecutor.StopLossType.Percentage,
            triggerValue: 1000, // 10% 止损
            trailingDistance: 0,
            minAmountOut: 0,
            poolFee: 3000
        });

        bytes32 strategyId = stopLossExecutor.createStrategy(params);

        vm.stopPrank();

        IStopLossExecutor.StopLossStrategy memory strategy = stopLossExecutor.getStrategy(strategyId);
        // 触发价格应该是 $2500 * 90% = $2250
        assertEq(strategy.triggerPrice, 2250e18);
    }

    function test_Percentage_ShouldTrigger() public {
        bytes32 strategyId = _createPercentageStrategy(user1, 1000); // 10%

        // 初始价格 $2500, 触发价格 $2250
        // 模拟 15% 下跌到 $2125
        priceOracle.simulatePriceDrop(address(weth), 1500);

        (bool triggered,) = stopLossExecutor.shouldTrigger(strategyId);
        assertTrue(triggered);
    }

    function test_Percentage_Execute_Success() public {
        bytes32 strategyId = _createPercentageStrategy(user1, 1000);

        vm.prank(user1);
        weth.approve(address(stopLossExecutor), type(uint256).max);

        // 模拟 15% 下跌
        priceOracle.simulatePriceDrop(address(weth), 1500);

        bool executed = stopLossExecutor.checkAndExecute(strategyId);
        assertTrue(executed);
    }

    // ==================== 追踪止损测试 ====================

    function test_CreateStrategy_TrailingStop_Success() public {
        vm.startPrank(user1);

        IStopLossExecutor.CreateStrategyParams memory params = IStopLossExecutor.CreateStrategyParams({
            tokenToSell: address(weth),
            tokenToReceive: address(usdc),
            amount: 1e18,
            stopLossType: IStopLossExecutor.StopLossType.TrailingStop,
            triggerValue: 0, // 不用于追踪止损
            trailingDistance: 1000, // 10% 追踪距离
            minAmountOut: 0,
            poolFee: 3000
        });

        bytes32 strategyId = stopLossExecutor.createStrategy(params);

        vm.stopPrank();

        IStopLossExecutor.StopLossStrategy memory strategy = stopLossExecutor.getStrategy(strategyId);
        assertEq(strategy.highestPrice, WETH_PRICE);
        // 触发价格 = $2500 * 90% = $2250
        assertEq(strategy.triggerPrice, 2250e18);
    }

    function test_TrailingStop_UpdateHighestPrice() public {
        bytes32 strategyId = _createTrailingStopStrategy(user1, 1000);

        // 价格上涨到 $3000
        priceOracle.setPrice(address(weth), 3000e18);

        stopLossExecutor.updateHighestPrice(strategyId, 3000e18);

        IStopLossExecutor.StopLossStrategy memory strategy = stopLossExecutor.getStrategy(strategyId);
        assertEq(strategy.highestPrice, 3000e18);
        // 新触发价格 = $3000 * 90% = $2700
        assertEq(strategy.triggerPrice, 2700e18);
    }

    function test_TrailingStop_AutoUpdate_OnCheckAndExecute() public {
        bytes32 strategyId = _createTrailingStopStrategy(user1, 1000);

        vm.prank(user1);
        weth.approve(address(stopLossExecutor), type(uint256).max);

        // 价格上涨到 $3000
        priceOracle.setPrice(address(weth), 3000e18);

        // checkAndExecute 应该更新最高价但不触发
        bool executed = stopLossExecutor.checkAndExecute(strategyId);
        assertFalse(executed); // 价格高于触发价，不执行

        IStopLossExecutor.StopLossStrategy memory strategy = stopLossExecutor.getStrategy(strategyId);
        assertEq(strategy.highestPrice, 3000e18);
    }

    function test_TrailingStop_Execute_AfterRise_ThenDrop() public {
        bytes32 strategyId = _createTrailingStopStrategy(user1, 1000);

        vm.prank(user1);
        weth.approve(address(stopLossExecutor), type(uint256).max);

        // 价格先涨到 $3000
        priceOracle.setPrice(address(weth), 3000e18);
        stopLossExecutor.checkAndExecute(strategyId);

        // 验证最高价更新
        IStopLossExecutor.StopLossStrategy memory strategy1 = stopLossExecutor.getStrategy(strategyId);
        assertEq(strategy1.highestPrice, 3000e18);
        assertEq(strategy1.triggerPrice, 2700e18); // $3000 * 90%

        // 价格下跌到 $2600 (低于 $2700 触发价)
        priceOracle.setPrice(address(weth), 2600e18);

        bool executed = stopLossExecutor.checkAndExecute(strategyId);
        assertTrue(executed);

        IStopLossExecutor.StopLossStrategy memory strategy2 = stopLossExecutor.getStrategy(strategyId);
        assertEq(uint(strategy2.status), uint(IStopLossExecutor.StrategyStatus.Triggered));
    }

    // ==================== 批量执行测试 ====================

    function test_BatchCheckAndExecute() public {
        bytes32 strategyId1 = _createFixedPriceStrategy(user1, 2000e18);
        vm.roll(block.number + 1);
        bytes32 strategyId2 = _createFixedPriceStrategy(user1, 2200e18);

        vm.prank(user1);
        weth.approve(address(stopLossExecutor), type(uint256).max);

        // 价格下跌到 $2100 (只触发 strategyId2)
        priceOracle.setPrice(address(weth), 2100e18);

        bytes32[] memory strategyIds = new bytes32[](2);
        strategyIds[0] = strategyId1;
        strategyIds[1] = strategyId2;

        uint256 executedCount = stopLossExecutor.batchCheckAndExecute(strategyIds);
        assertEq(executedCount, 1); // 只有 strategyId2 触发

        // 价格再下跌到 $1900
        priceOracle.setPrice(address(weth), 1900e18);

        executedCount = stopLossExecutor.batchCheckAndExecute(strategyIds);
        assertEq(executedCount, 1); // strategyId1 触发, strategyId2 已经触发过
    }

    // ==================== 策略控制测试 ====================

    function test_PauseStrategy() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit StrategyPaused(strategyId, block.timestamp);
        stopLossExecutor.pauseStrategy(strategyId);

        IStopLossExecutor.StopLossStrategy memory strategy = stopLossExecutor.getStrategy(strategyId);
        assertEq(uint(strategy.status), uint(IStopLossExecutor.StrategyStatus.Paused));
    }

    function test_PausedStrategy_NotExecuted() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        vm.prank(user1);
        stopLossExecutor.pauseStrategy(strategyId);

        // 价格下跌
        priceOracle.setPrice(address(weth), 1900e18);

        // 尝试执行应该返回 false
        bool executed = stopLossExecutor.checkAndExecute(strategyId);
        assertFalse(executed);
    }

    function test_ResumeStrategy() public {
        bytes32 strategyId = _createTrailingStopStrategy(user1, 1000);

        vm.startPrank(user1);
        stopLossExecutor.pauseStrategy(strategyId);

        // 价格上涨
        priceOracle.setPrice(address(weth), 3000e18);

        vm.expectEmit(true, false, false, true);
        emit StrategyResumed(strategyId, block.timestamp);
        stopLossExecutor.resumeStrategy(strategyId);
        vm.stopPrank();

        IStopLossExecutor.StopLossStrategy memory strategy = stopLossExecutor.getStrategy(strategyId);
        assertEq(uint(strategy.status), uint(IStopLossExecutor.StrategyStatus.Active));
        // 恢复时应该用当前价格更新最高价
        assertEq(strategy.highestPrice, 3000e18);
    }

    function test_CancelStrategy() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit StrategyCancelled(strategyId, block.timestamp);
        stopLossExecutor.cancelStrategy(strategyId);

        IStopLossExecutor.StopLossStrategy memory strategy = stopLossExecutor.getStrategy(strategyId);
        assertEq(uint(strategy.status), uint(IStopLossExecutor.StrategyStatus.Cancelled));
    }

    function test_RevertWhen_CancelTriggeredStrategy() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        vm.prank(user1);
        weth.approve(address(stopLossExecutor), type(uint256).max);

        priceOracle.setPrice(address(weth), 1900e18);
        stopLossExecutor.checkAndExecute(strategyId);

        vm.prank(user1);
        vm.expectRevert("Already triggered");
        stopLossExecutor.cancelStrategy(strategyId);
    }

    function test_RevertWhen_NonOwnerPausesStrategy() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        vm.prank(user2);
        vm.expectRevert(IStopLossExecutor.NotStrategyOwner.selector);
        stopLossExecutor.pauseStrategy(strategyId);
    }

    function test_UpdateStrategy() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        vm.prank(user1);
        stopLossExecutor.updateStrategy(strategyId, 1800e18, 1500e6);

        IStopLossExecutor.StopLossStrategy memory strategy = stopLossExecutor.getStrategy(strategyId);
        assertEq(strategy.triggerPrice, 1800e18);
        assertEq(strategy.minAmountOut, 1500e6);
    }

    // ==================== 视图函数测试 ====================

    function test_GetUserStrategies() public {
        bytes32 strategyId1 = _createFixedPriceStrategy(user1, 2000e18);
        vm.roll(block.number + 1);
        bytes32 strategyId2 = _createPercentageStrategy(user1, 1000);

        bytes32[] memory strategies = stopLossExecutor.getUserStrategies(user1);
        assertEq(strategies.length, 2);
        assertEq(strategies[0], strategyId1);
        assertEq(strategies[1], strategyId2);
    }

    function test_GetPendingStrategies() public {
        bytes32 strategyId1 = _createFixedPriceStrategy(user1, 2000e18);  // 触发价 $2000
        vm.roll(block.number + 1);
        bytes32 strategyId2 = _createFixedPriceStrategy(user1, 2600e18); // 触发价 $2600

        // 价格下跌到 $2100
        priceOracle.setPrice(address(weth), 2100e18);

        bytes32[] memory pending = stopLossExecutor.getPendingStrategies(10);
        // 在 $2100 时:
        // - strategyId1 ($2000 触发价): $2100 > $2000, 不触发
        // - strategyId2 ($2600 触发价): $2100 < $2600, 触发
        assertEq(pending.length, 1);
        assertEq(pending[0], strategyId2); // 只有 $2600 触发价的会在 $2100 时触发
    }

    function test_GetCurrentTriggerPrice() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        uint256 triggerPrice = stopLossExecutor.getCurrentTriggerPrice(strategyId);
        assertEq(triggerPrice, 2000e18);
    }

    function test_GetExecutionHistory() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        vm.prank(user1);
        weth.approve(address(stopLossExecutor), type(uint256).max);

        priceOracle.setPrice(address(weth), 1900e18);
        stopLossExecutor.checkAndExecute(strategyId);

        IStopLossExecutor.ExecutionRecord[] memory history = stopLossExecutor.getExecutionHistory(strategyId);
        assertEq(history.length, 1);
        assertEq(history[0].amountSold, 1e18);
        assertTrue(history[0].amountReceived > 0);
    }

    // ==================== 参数验证测试 ====================

    function test_RevertWhen_CreateWithZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(IStopLossExecutor.InvalidParameters.selector);

        IStopLossExecutor.CreateStrategyParams memory params = IStopLossExecutor.CreateStrategyParams({
            tokenToSell: address(weth),
            tokenToReceive: address(usdc),
            amount: 0,
            stopLossType: IStopLossExecutor.StopLossType.FixedPrice,
            triggerValue: 2000e18,
            trailingDistance: 0,
            minAmountOut: 0,
            poolFee: 3000
        });

        stopLossExecutor.createStrategy(params);
    }

    function test_RevertWhen_CreateWithSameTokens() public {
        vm.prank(user1);
        vm.expectRevert(IStopLossExecutor.InvalidParameters.selector);

        IStopLossExecutor.CreateStrategyParams memory params = IStopLossExecutor.CreateStrategyParams({
            tokenToSell: address(weth),
            tokenToReceive: address(weth),
            amount: 1e18,
            stopLossType: IStopLossExecutor.StopLossType.FixedPrice,
            triggerValue: 2000e18,
            trailingDistance: 0,
            minAmountOut: 0,
            poolFee: 3000
        });

        stopLossExecutor.createStrategy(params);
    }

    function test_RevertWhen_CreateWithLowPercentage() public {
        vm.prank(user1);
        vm.expectRevert(IStopLossExecutor.InvalidParameters.selector);

        IStopLossExecutor.CreateStrategyParams memory params = IStopLossExecutor.CreateStrategyParams({
            tokenToSell: address(weth),
            tokenToReceive: address(usdc),
            amount: 1e18,
            stopLossType: IStopLossExecutor.StopLossType.Percentage,
            triggerValue: 50, // < MIN_STOP_PERCENTAGE (100)
            trailingDistance: 0,
            minAmountOut: 0,
            poolFee: 3000
        });

        stopLossExecutor.createStrategy(params);
    }

    function test_RevertWhen_CreateWithHighPercentage() public {
        vm.prank(user1);
        vm.expectRevert(IStopLossExecutor.InvalidParameters.selector);

        IStopLossExecutor.CreateStrategyParams memory params = IStopLossExecutor.CreateStrategyParams({
            tokenToSell: address(weth),
            tokenToReceive: address(usdc),
            amount: 1e18,
            stopLossType: IStopLossExecutor.StopLossType.Percentage,
            triggerValue: 6000, // > MAX_STOP_PERCENTAGE (5000)
            trailingDistance: 0,
            minAmountOut: 0,
            poolFee: 3000
        });

        stopLossExecutor.createStrategy(params);
    }

    // ==================== 管理函数测试 ====================

    function test_SetProtocolFee() public {
        stopLossExecutor.setProtocolFee(50);
        assertEq(stopLossExecutor.protocolFeeBps(), 50);
    }

    function test_RevertWhen_SetFeeTooHigh() public {
        vm.expectRevert("Fee too high");
        stopLossExecutor.setProtocolFee(101);
    }

    function test_SetFeeRecipient() public {
        address newRecipient = makeAddr("feeRecipient");
        stopLossExecutor.setFeeRecipient(newRecipient);
        assertEq(stopLossExecutor.feeRecipient(), newRecipient);
    }

    function test_SetPriceOracle() public {
        MockPriceOracle newOracle = new MockPriceOracle();
        stopLossExecutor.setPriceOracle(address(newOracle));
        assertEq(address(stopLossExecutor.priceOracle()), address(newOracle));
    }

    function test_Pause() public {
        stopLossExecutor.pause();

        vm.prank(user1);
        IStopLossExecutor.CreateStrategyParams memory params = IStopLossExecutor.CreateStrategyParams({
            tokenToSell: address(weth),
            tokenToReceive: address(usdc),
            amount: 1e18,
            stopLossType: IStopLossExecutor.StopLossType.FixedPrice,
            triggerValue: 2000e18,
            trailingDistance: 0,
            minAmountOut: 0,
            poolFee: 3000
        });

        vm.expectRevert();
        stopLossExecutor.createStrategy(params);
    }

    function test_EmergencyWithdraw() public {
        weth.mint(address(stopLossExecutor), 10e18);

        address recipient = makeAddr("recipient");
        stopLossExecutor.emergencyWithdraw(address(weth), recipient, 10e18);

        assertEq(weth.balanceOf(recipient), 10e18);
    }

    // ==================== 补充覆盖测试 ====================

    function test_Unpause() public {
        stopLossExecutor.pause();
        stopLossExecutor.unpause();

        // 验证可以创建策略
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);
        assertTrue(strategyId != bytes32(0));
    }

    function test_RevertWhen_StrategyNotFound() public {
        bytes32 fakeId = keccak256("fake");
        vm.expectRevert(IStopLossExecutor.StrategyNotFound.selector);
        stopLossExecutor.getStrategy(fakeId);
    }

    function test_RevertWhen_CreateWithZeroTriggerPrice() public {
        vm.prank(user1);
        vm.expectRevert(IStopLossExecutor.InvalidParameters.selector);

        IStopLossExecutor.CreateStrategyParams memory params = IStopLossExecutor.CreateStrategyParams({
            tokenToSell: address(weth),
            tokenToReceive: address(usdc),
            amount: 1e18,
            stopLossType: IStopLossExecutor.StopLossType.FixedPrice,
            triggerValue: 0, // 无效
            trailingDistance: 0,
            minAmountOut: 0,
            poolFee: 3000
        });

        stopLossExecutor.createStrategy(params);
    }

    function test_RevertWhen_CreateWithZeroTokenToSell() public {
        vm.prank(user1);
        vm.expectRevert(IStopLossExecutor.InvalidParameters.selector);

        IStopLossExecutor.CreateStrategyParams memory params = IStopLossExecutor.CreateStrategyParams({
            tokenToSell: address(0),
            tokenToReceive: address(usdc),
            amount: 1e18,
            stopLossType: IStopLossExecutor.StopLossType.FixedPrice,
            triggerValue: 2000e18,
            trailingDistance: 0,
            minAmountOut: 0,
            poolFee: 3000
        });

        stopLossExecutor.createStrategy(params);
    }

    function test_RevertWhen_CreateWithZeroTokenToReceive() public {
        vm.prank(user1);
        vm.expectRevert(IStopLossExecutor.InvalidParameters.selector);

        IStopLossExecutor.CreateStrategyParams memory params = IStopLossExecutor.CreateStrategyParams({
            tokenToSell: address(weth),
            tokenToReceive: address(0),
            amount: 1e18,
            stopLossType: IStopLossExecutor.StopLossType.FixedPrice,
            triggerValue: 2000e18,
            trailingDistance: 0,
            minAmountOut: 0,
            poolFee: 3000
        });

        stopLossExecutor.createStrategy(params);
    }

    function test_RevertWhen_CreateTrailingWithLowDistance() public {
        vm.prank(user1);
        vm.expectRevert(IStopLossExecutor.InvalidParameters.selector);

        IStopLossExecutor.CreateStrategyParams memory params = IStopLossExecutor.CreateStrategyParams({
            tokenToSell: address(weth),
            tokenToReceive: address(usdc),
            amount: 1e18,
            stopLossType: IStopLossExecutor.StopLossType.TrailingStop,
            triggerValue: 0,
            trailingDistance: 50, // < MIN_STOP_PERCENTAGE
            minAmountOut: 0,
            poolFee: 3000
        });

        stopLossExecutor.createStrategy(params);
    }

    function test_RevertWhen_CreateTrailingWithHighDistance() public {
        vm.prank(user1);
        vm.expectRevert(IStopLossExecutor.InvalidParameters.selector);

        IStopLossExecutor.CreateStrategyParams memory params = IStopLossExecutor.CreateStrategyParams({
            tokenToSell: address(weth),
            tokenToReceive: address(usdc),
            amount: 1e18,
            stopLossType: IStopLossExecutor.StopLossType.TrailingStop,
            triggerValue: 0,
            trailingDistance: 6000, // > MAX_STOP_PERCENTAGE
            minAmountOut: 0,
            poolFee: 3000
        });

        stopLossExecutor.createStrategy(params);
    }

    function test_ShouldTrigger_StrategyNotFound() public {
        bytes32 fakeId = keccak256("fake");
        (bool triggered, uint256 price) = stopLossExecutor.shouldTrigger(fakeId);
        assertFalse(triggered);
        assertEq(price, 0);
    }

    function test_ShouldTrigger_StrategyNotActive() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        vm.prank(user1);
        stopLossExecutor.pauseStrategy(strategyId);

        (bool triggered, uint256 price) = stopLossExecutor.shouldTrigger(strategyId);
        assertFalse(triggered);
        assertEq(price, 0);
    }

    function test_CheckAndExecute_StrategyNotActive() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        vm.prank(user1);
        stopLossExecutor.pauseStrategy(strategyId);

        priceOracle.setPrice(address(weth), 1900e18);

        bool executed = stopLossExecutor.checkAndExecute(strategyId);
        assertFalse(executed);
    }

    function test_RevertWhen_PausePausedStrategy() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        vm.startPrank(user1);
        stopLossExecutor.pauseStrategy(strategyId);

        vm.expectRevert(IStopLossExecutor.StrategyNotActive.selector);
        stopLossExecutor.pauseStrategy(strategyId);
        vm.stopPrank();
    }

    function test_RevertWhen_ResumeActiveStrategy() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        vm.prank(user1);
        vm.expectRevert("Not paused");
        stopLossExecutor.resumeStrategy(strategyId);
    }

    function test_RevertWhen_CancelCancelledStrategy() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        vm.startPrank(user1);
        stopLossExecutor.cancelStrategy(strategyId);

        vm.expectRevert("Already cancelled");
        stopLossExecutor.cancelStrategy(strategyId);
        vm.stopPrank();
    }

    function test_RevertWhen_UpdateInactiveStrategy() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        vm.startPrank(user1);
        stopLossExecutor.pauseStrategy(strategyId);

        vm.expectRevert(IStopLossExecutor.StrategyNotActive.selector);
        stopLossExecutor.updateStrategy(strategyId, 1800e18, 1500e6);
        vm.stopPrank();
    }

    function test_RevertWhen_UpdateFixedPriceWithZero() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        vm.prank(user1);
        vm.expectRevert(IStopLossExecutor.InvalidParameters.selector);
        stopLossExecutor.updateStrategy(strategyId, 0, 1500e6);
    }

    function test_UpdateStrategy_Percentage() public {
        bytes32 strategyId = _createPercentageStrategy(user1, 1000);

        vm.prank(user1);
        stopLossExecutor.updateStrategy(strategyId, 1500, 1000e6); // 更新到 15%

        IStopLossExecutor.StopLossStrategy memory strategy = stopLossExecutor.getStrategy(strategyId);
        assertEq(strategy.triggerPercentage, 1500);
    }

    function test_RevertWhen_UpdatePercentageTooLow() public {
        bytes32 strategyId = _createPercentageStrategy(user1, 1000);

        vm.prank(user1);
        vm.expectRevert(IStopLossExecutor.InvalidParameters.selector);
        stopLossExecutor.updateStrategy(strategyId, 50, 1000e6); // < MIN_STOP_PERCENTAGE
    }

    function test_RevertWhen_UpdatePercentageTooHigh() public {
        bytes32 strategyId = _createPercentageStrategy(user1, 1000);

        vm.prank(user1);
        vm.expectRevert(IStopLossExecutor.InvalidParameters.selector);
        stopLossExecutor.updateStrategy(strategyId, 6000, 1000e6); // > MAX_STOP_PERCENTAGE
    }

    function test_UpdateStrategy_TrailingStop() public {
        bytes32 strategyId = _createTrailingStopStrategy(user1, 1000);

        vm.prank(user1);
        stopLossExecutor.updateStrategy(strategyId, 1500, 1000e6); // 更新到 15%

        IStopLossExecutor.StopLossStrategy memory strategy = stopLossExecutor.getStrategy(strategyId);
        assertEq(strategy.trailingDistance, 1500);
    }

    function test_RevertWhen_UpdateTrailingTooLow() public {
        bytes32 strategyId = _createTrailingStopStrategy(user1, 1000);

        vm.prank(user1);
        vm.expectRevert(IStopLossExecutor.InvalidParameters.selector);
        stopLossExecutor.updateStrategy(strategyId, 50, 1000e6);
    }

    function test_RevertWhen_UpdateTrailingTooHigh() public {
        bytes32 strategyId = _createTrailingStopStrategy(user1, 1000);

        vm.prank(user1);
        vm.expectRevert(IStopLossExecutor.InvalidParameters.selector);
        stopLossExecutor.updateStrategy(strategyId, 6000, 1000e6);
    }

    function test_RevertWhen_UpdateHighestPriceNonTrailing() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        vm.expectRevert(IStopLossExecutor.InvalidParameters.selector);
        stopLossExecutor.updateHighestPrice(strategyId, 3000e18);
    }

    function test_RevertWhen_UpdateHighestPriceInactiveStrategy() public {
        bytes32 strategyId = _createTrailingStopStrategy(user1, 1000);

        vm.prank(user1);
        stopLossExecutor.pauseStrategy(strategyId);

        vm.expectRevert(IStopLossExecutor.StrategyNotActive.selector);
        stopLossExecutor.updateHighestPrice(strategyId, 3000e18);
    }

    function test_UpdateHighestPrice_NoUpdateIfLower() public {
        bytes32 strategyId = _createTrailingStopStrategy(user1, 1000);

        // 尝试用更低的价格更新
        stopLossExecutor.updateHighestPrice(strategyId, 2000e18);

        IStopLossExecutor.StopLossStrategy memory strategy = stopLossExecutor.getStrategy(strategyId);
        assertEq(strategy.highestPrice, WETH_PRICE); // 应该保持不变
    }

    function test_Execute_WithPartialBalance() public {
        bytes32 strategyId = _createFixedPriceStrategy(user1, 2000e18);

        // user1 只保留 0.5 WETH
        vm.prank(user1);
        weth.transfer(address(1), 9.5e18);

        vm.prank(user1);
        weth.approve(address(stopLossExecutor), type(uint256).max);

        priceOracle.setPrice(address(weth), 1900e18);

        bool executed = stopLossExecutor.checkAndExecute(strategyId);
        assertTrue(executed);

        IStopLossExecutor.StopLossStrategy memory strategy = stopLossExecutor.getStrategy(strategyId);
        // 执行金额应该是用户实际余额
        assertTrue(strategy.executedAmount <= 0.5e18);
    }

    function test_BatchCheckAndExecute_AllFail() public {
        bytes32 strategyId1 = _createFixedPriceStrategy(user1, 2000e18);
        vm.roll(block.number + 1);
        bytes32 strategyId2 = _createFixedPriceStrategy(user1, 2000e18);

        // 价格高于触发价，不会触发
        priceOracle.setPrice(address(weth), 2500e18);

        bytes32[] memory strategyIds = new bytes32[](2);
        strategyIds[0] = strategyId1;
        strategyIds[1] = strategyId2;

        uint256 executedCount = stopLossExecutor.batchCheckAndExecute(strategyIds);
        assertEq(executedCount, 0);
    }

    function test_ResumeStrategy_UpdatesHighestPrice() public {
        bytes32 strategyId = _createTrailingStopStrategy(user1, 1000);

        vm.prank(user1);
        stopLossExecutor.pauseStrategy(strategyId);

        // 价格上涨
        priceOracle.setPrice(address(weth), 3000e18);

        vm.prank(user1);
        stopLossExecutor.resumeStrategy(strategyId);

        IStopLossExecutor.StopLossStrategy memory strategy = stopLossExecutor.getStrategy(strategyId);
        assertEq(strategy.highestPrice, 3000e18);
        // 新触发价 = 3000 * 90% = 2700
        assertEq(strategy.triggerPrice, 2700e18);
    }

    function test_ReceiveEther() public {
        (bool success,) = address(stopLossExecutor).call{value: 1 ether}("");
        assertTrue(success);
    }

    function test_GetPendingStrategies_Empty() public {
        // 没有策略触发
        bytes32[] memory pending = stopLossExecutor.getPendingStrategies(10);
        assertEq(pending.length, 0);
    }

    function test_GetPendingStrategies_LimitExceeded() public {
        // 创建多个策略
        for (uint i = 0; i < 5; i++) {
            vm.roll(block.number + 1);
            _createFixedPriceStrategy(user1, 2600e18);
        }

        priceOracle.setPrice(address(weth), 2100e18);

        // 限制返回 3 个
        bytes32[] memory pending = stopLossExecutor.getPendingStrategies(3);
        assertEq(pending.length, 3);
    }

    // ==================== 辅助函数 ====================

    function _createFixedPriceStrategy(address user, uint256 triggerPrice) internal returns (bytes32) {
        vm.prank(user);

        IStopLossExecutor.CreateStrategyParams memory params = IStopLossExecutor.CreateStrategyParams({
            tokenToSell: address(weth),
            tokenToReceive: address(usdc),
            amount: 1e18,
            stopLossType: IStopLossExecutor.StopLossType.FixedPrice,
            triggerValue: triggerPrice,
            trailingDistance: 0,
            minAmountOut: 0,
            poolFee: 3000
        });

        return stopLossExecutor.createStrategy(params);
    }

    function _createPercentageStrategy(address user, uint256 percentage) internal returns (bytes32) {
        vm.prank(user);

        IStopLossExecutor.CreateStrategyParams memory params = IStopLossExecutor.CreateStrategyParams({
            tokenToSell: address(weth),
            tokenToReceive: address(usdc),
            amount: 1e18,
            stopLossType: IStopLossExecutor.StopLossType.Percentage,
            triggerValue: percentage,
            trailingDistance: 0,
            minAmountOut: 0,
            poolFee: 3000
        });

        return stopLossExecutor.createStrategy(params);
    }

    function _createTrailingStopStrategy(address user, uint256 trailingDistance) internal returns (bytes32) {
        vm.prank(user);

        IStopLossExecutor.CreateStrategyParams memory params = IStopLossExecutor.CreateStrategyParams({
            tokenToSell: address(weth),
            tokenToReceive: address(usdc),
            amount: 1e18,
            stopLossType: IStopLossExecutor.StopLossType.TrailingStop,
            triggerValue: 0,
            trailingDistance: trailingDistance,
            minAmountOut: 0,
            poolFee: 3000
        });

        return stopLossExecutor.createStrategy(params);
    }
}
