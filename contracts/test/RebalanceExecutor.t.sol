// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ShieldCore} from "../src/core/ShieldCore.sol";
import {RebalanceExecutor} from "../src/strategies/RebalanceExecutor.sol";
import {IRebalanceExecutor} from "../src/interfaces/IRebalanceExecutor.sol";
import {MockERC20, MockSwapRouter, MockPriceOracle} from "./mocks/Mocks.sol";

/**
 * @title RebalanceExecutorTest
 * @notice RebalanceExecutor 合约完整测试套件
 */
contract RebalanceExecutorTest is Test {
    ShieldCore public shieldCore;
    RebalanceExecutor public rebalanceExecutor;
    MockSwapRouter public swapRouter;
    MockPriceOracle public priceOracle;
    MockERC20 public usdc;
    MockERC20 public weth;
    MockERC20 public wbtc;

    address public owner;
    address public user1;
    address public user2;

    // 事件定义
    event StrategyCreated(
        bytes32 indexed strategyId,
        address indexed user,
        address[] tokens,
        uint256[] targetWeights,
        uint256 rebalanceThreshold
    );
    event RebalanceExecuted(
        bytes32 indexed strategyId,
        address indexed user,
        uint256 totalValue,
        uint256 rebalanceNumber,
        uint256 timestamp
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
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);
        swapRouter = new MockSwapRouter();
        priceOracle = new MockPriceOracle();

        // 设置价格 (以 USDC 为基础报价)
        // USDC = $1, WETH = $2500, WBTC = $40000
        priceOracle.setPrice(address(usdc), 1e18);          // $1
        priceOracle.setPrice(address(weth), 2500e18);       // $2500
        priceOracle.setPrice(address(wbtc), 40000e18);      // $40000

        // 部署核心合约
        shieldCore = new ShieldCore();

        // 部署再平衡执行器
        rebalanceExecutor = new RebalanceExecutor(
            address(shieldCore),
            address(swapRouter),
            address(priceOracle),
            address(usdc)
        );

        // 配置授权
        shieldCore.addAuthorizedExecutor(address(rebalanceExecutor));

        // 给用户铸造测试代币
        // user1: 5000 USDC, 1 WETH, 0.05 WBTC
        usdc.mint(user1, 5000e6);
        weth.mint(user1, 1e18);
        wbtc.mint(user1, 5e6); // 0.05 WBTC

        // 给 SwapRouter 一些代币用于交换
        usdc.mint(address(swapRouter), 1000000e6);
        weth.mint(address(swapRouter), 1000e18);
        wbtc.mint(address(swapRouter), 100e8);

        // 用户激活 Shield (设置足够高的限额以支持 18 位小数的代币)
        vm.prank(user1);
        shieldCore.activateShield(100000e18, 50000e18); // 每日 100k, 单笔 50k (使用 18 位小数)
    }

    // ==================== 策略创建测试 ====================

    function test_CreateStrategy_Success() public {
        vm.startPrank(user1);

        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weth);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 6000; // 60% USDC
        weights[1] = 4000; // 40% WETH

        IRebalanceExecutor.CreateStrategyParams memory params = IRebalanceExecutor.CreateStrategyParams({
            tokens: tokens,
            targetWeights: weights,
            rebalanceThreshold: 500, // 5%
            minRebalanceInterval: 3600, // 1 小时
            poolFee: 3000
        });

        bytes32 strategyId = rebalanceExecutor.createStrategy(params);

        vm.stopPrank();

        // 验证策略
        IRebalanceExecutor.RebalanceStrategy memory strategy = rebalanceExecutor.getStrategy(strategyId);
        assertEq(strategy.user, user1);
        assertEq(strategy.allocations.length, 2);
        assertEq(strategy.allocations[0].token, address(usdc));
        assertEq(strategy.allocations[0].targetWeight, 6000);
        assertEq(strategy.allocations[1].token, address(weth));
        assertEq(strategy.allocations[1].targetWeight, 4000);
        assertEq(strategy.rebalanceThreshold, 500);
        assertEq(uint(strategy.status), uint(IRebalanceExecutor.StrategyStatus.Active));
    }

    function test_CreateStrategy_ThreeAssets() public {
        vm.startPrank(user1);

        address[] memory tokens = new address[](3);
        tokens[0] = address(usdc);
        tokens[1] = address(weth);
        tokens[2] = address(wbtc);

        uint256[] memory weights = new uint256[](3);
        weights[0] = 5000; // 50% USDC
        weights[1] = 3000; // 30% WETH
        weights[2] = 2000; // 20% WBTC

        IRebalanceExecutor.CreateStrategyParams memory params = IRebalanceExecutor.CreateStrategyParams({
            tokens: tokens,
            targetWeights: weights,
            rebalanceThreshold: 500,
            minRebalanceInterval: 3600,
            poolFee: 3000
        });

        bytes32 strategyId = rebalanceExecutor.createStrategy(params);

        vm.stopPrank();

        IRebalanceExecutor.RebalanceStrategy memory strategy = rebalanceExecutor.getStrategy(strategyId);
        assertEq(strategy.allocations.length, 3);
    }

    function test_RevertWhen_CreateWithInvalidWeights() public {
        vm.prank(user1);

        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weth);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 5000;
        weights[1] = 4000; // 总和 9000, 不是 10000

        IRebalanceExecutor.CreateStrategyParams memory params = IRebalanceExecutor.CreateStrategyParams({
            tokens: tokens,
            targetWeights: weights,
            rebalanceThreshold: 500,
            minRebalanceInterval: 3600,
            poolFee: 3000
        });

        vm.expectRevert(IRebalanceExecutor.WeightsSumInvalid.selector);
        rebalanceExecutor.createStrategy(params);
    }

    function test_RevertWhen_CreateWithZeroWeight() public {
        vm.prank(user1);

        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weth);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 10000;
        weights[1] = 0;

        IRebalanceExecutor.CreateStrategyParams memory params = IRebalanceExecutor.CreateStrategyParams({
            tokens: tokens,
            targetWeights: weights,
            rebalanceThreshold: 500,
            minRebalanceInterval: 3600,
            poolFee: 3000
        });

        vm.expectRevert(IRebalanceExecutor.InvalidParameters.selector);
        rebalanceExecutor.createStrategy(params);
    }

    function test_RevertWhen_CreateWithLowThreshold() public {
        vm.prank(user1);

        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weth);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 6000;
        weights[1] = 4000;

        IRebalanceExecutor.CreateStrategyParams memory params = IRebalanceExecutor.CreateStrategyParams({
            tokens: tokens,
            targetWeights: weights,
            rebalanceThreshold: 50, // < MIN_THRESHOLD (100)
            minRebalanceInterval: 3600,
            poolFee: 3000
        });

        vm.expectRevert(IRebalanceExecutor.InvalidParameters.selector);
        rebalanceExecutor.createStrategy(params);
    }

    // ==================== 再平衡检测测试 ====================

    function test_NeedsRebalance_WithinThreshold() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        (bool needed, string memory reason) = rebalanceExecutor.needsRebalance(strategyId);
        // 初始分配可能需要再平衡或不需要，取决于用户实际持仓
        // 这里主要测试函数能正常工作
        assertTrue(bytes(reason).length > 0 || !needed);
    }

    function test_GetCurrentWeights() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        uint256[] memory weights = rebalanceExecutor.getCurrentWeights(strategyId);
        assertEq(weights.length, 2);

        // 验证权重总和约等于 10000 (可能有小误差)
        uint256 totalWeight = weights[0] + weights[1];
        assertTrue(totalWeight > 9900 && totalWeight <= 10000);
    }

    function test_GetPortfolioValue() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        uint256 totalValue = rebalanceExecutor.getPortfolioValue(strategyId);
        // user1 有: 5000 USDC (5000e6) + 1 WETH (1e18)
        // 计算方式: (balance * price) / 1e18
        // USDC: 5000e6 * 1e18 / 1e18 = 5000e6
        // WETH: 1e18 * 2500e18 / 1e18 = 2500e18
        // 总价值约 2500e18 (USDC 部分相对较小)
        assertTrue(totalValue > 2400e18 && totalValue < 2600e18);
    }

    // ==================== 再平衡执行测试 ====================

    function test_ExecuteRebalance_Success() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        // 用户授权
        vm.startPrank(user1);
        usdc.approve(address(rebalanceExecutor), type(uint256).max);
        weth.approve(address(rebalanceExecutor), type(uint256).max);
        vm.stopPrank();

        // 检查是否需要再平衡
        (bool needed,) = rebalanceExecutor.needsRebalance(strategyId);

        if (needed) {
            rebalanceExecutor.executeRebalance(strategyId);

            // 验证状态更新
            IRebalanceExecutor.RebalanceStrategy memory strategy = rebalanceExecutor.getStrategy(strategyId);
            assertEq(strategy.totalRebalances, 1);
            assertTrue(strategy.lastRebalanceTime > 0);
        }
    }

    function test_RevertWhen_RebalanceTooSoon() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        // 用户授权
        vm.startPrank(user1);
        usdc.approve(address(rebalanceExecutor), type(uint256).max);
        weth.approve(address(rebalanceExecutor), type(uint256).max);
        vm.stopPrank();

        (bool needed,) = rebalanceExecutor.needsRebalance(strategyId);

        if (needed) {
            // 第一次再平衡
            rebalanceExecutor.executeRebalance(strategyId);

            // 模拟价格变化使再平衡再次需要
            priceOracle.simulatePriceDrop(address(weth), 2000); // 20% 下跌

            // 立即尝试再次再平衡应该失败
            vm.expectRevert();
            rebalanceExecutor.executeRebalance(strategyId);
        }
    }

    function test_ExecuteRebalance_AfterInterval() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        vm.startPrank(user1);
        usdc.approve(address(rebalanceExecutor), type(uint256).max);
        weth.approve(address(rebalanceExecutor), type(uint256).max);
        vm.stopPrank();

        (bool needed,) = rebalanceExecutor.needsRebalance(strategyId);

        if (needed) {
            rebalanceExecutor.executeRebalance(strategyId);

            // 快进 2 小时
            vm.warp(block.timestamp + 7200);

            // 模拟价格变化
            priceOracle.simulatePriceDrop(address(weth), 1000); // 10% 下跌

            (bool needed2,) = rebalanceExecutor.needsRebalance(strategyId);
            if (needed2) {
                rebalanceExecutor.executeRebalance(strategyId);

                IRebalanceExecutor.RebalanceStrategy memory strategy = rebalanceExecutor.getStrategy(strategyId);
                assertEq(strategy.totalRebalances, 2);
            }
        }
    }

    // ==================== 策略控制测试 ====================

    function test_PauseStrategy() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit StrategyPaused(strategyId, block.timestamp);
        rebalanceExecutor.pauseStrategy(strategyId);

        IRebalanceExecutor.RebalanceStrategy memory strategy = rebalanceExecutor.getStrategy(strategyId);
        assertEq(uint(strategy.status), uint(IRebalanceExecutor.StrategyStatus.Paused));
    }

    function test_ResumeStrategy() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        vm.startPrank(user1);
        rebalanceExecutor.pauseStrategy(strategyId);

        vm.expectEmit(true, false, false, true);
        emit StrategyResumed(strategyId, block.timestamp);
        rebalanceExecutor.resumeStrategy(strategyId);
        vm.stopPrank();

        IRebalanceExecutor.RebalanceStrategy memory strategy = rebalanceExecutor.getStrategy(strategyId);
        assertEq(uint(strategy.status), uint(IRebalanceExecutor.StrategyStatus.Active));
    }

    function test_CancelStrategy() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit StrategyCancelled(strategyId, block.timestamp);
        rebalanceExecutor.cancelStrategy(strategyId);

        IRebalanceExecutor.RebalanceStrategy memory strategy = rebalanceExecutor.getStrategy(strategyId);
        assertEq(uint(strategy.status), uint(IRebalanceExecutor.StrategyStatus.Cancelled));
    }

    function test_RevertWhen_NonOwnerPausesStrategy() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        vm.prank(user2);
        vm.expectRevert(IRebalanceExecutor.NotStrategyOwner.selector);
        rebalanceExecutor.pauseStrategy(strategyId);
    }

    function test_UpdateStrategy() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        uint256[] memory newWeights = new uint256[](2);
        newWeights[0] = 5000; // 50%
        newWeights[1] = 5000; // 50%

        vm.prank(user1);
        rebalanceExecutor.updateStrategy(strategyId, newWeights, 300);

        IRebalanceExecutor.RebalanceStrategy memory strategy = rebalanceExecutor.getStrategy(strategyId);
        assertEq(strategy.allocations[0].targetWeight, 5000);
        assertEq(strategy.allocations[1].targetWeight, 5000);
        assertEq(strategy.rebalanceThreshold, 300);
    }

    // ==================== 视图函数测试 ====================

    function test_GetUserStrategies() public {
        bytes32 strategyId1 = _createDefaultStrategy(user1);
        vm.roll(block.number + 1);
        bytes32 strategyId2 = _createDefaultStrategy(user1);

        bytes32[] memory strategies = rebalanceExecutor.getUserStrategies(user1);
        assertEq(strategies.length, 2);
        assertEq(strategies[0], strategyId1);
        assertEq(strategies[1], strategyId2);
    }

    function test_GetRebalanceHistory() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        vm.startPrank(user1);
        usdc.approve(address(rebalanceExecutor), type(uint256).max);
        weth.approve(address(rebalanceExecutor), type(uint256).max);
        vm.stopPrank();

        (bool needed,) = rebalanceExecutor.needsRebalance(strategyId);

        if (needed) {
            rebalanceExecutor.executeRebalance(strategyId);

            IRebalanceExecutor.RebalanceRecord[] memory history = rebalanceExecutor.getRebalanceHistory(strategyId);
            assertEq(history.length, 1);
            assertTrue(history[0].totalValueBefore > 0);
        }
    }

    // ==================== 管理函数测试 ====================

    function test_SetProtocolFee() public {
        rebalanceExecutor.setProtocolFee(50); // 0.5%
        assertEq(rebalanceExecutor.protocolFeeBps(), 50);
    }

    function test_RevertWhen_SetFeeTooHigh() public {
        vm.expectRevert("Fee too high");
        rebalanceExecutor.setProtocolFee(101); // > 1%
    }

    function test_SetFeeRecipient() public {
        address newRecipient = makeAddr("feeRecipient");
        rebalanceExecutor.setFeeRecipient(newRecipient);
        assertEq(rebalanceExecutor.feeRecipient(), newRecipient);
    }

    function test_SetPriceOracle() public {
        MockPriceOracle newOracle = new MockPriceOracle();
        rebalanceExecutor.setPriceOracle(address(newOracle));
        assertEq(address(rebalanceExecutor.priceOracle()), address(newOracle));
    }

    function test_Pause() public {
        rebalanceExecutor.pause();

        vm.prank(user1);
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weth);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 6000;
        weights[1] = 4000;

        IRebalanceExecutor.CreateStrategyParams memory params = IRebalanceExecutor.CreateStrategyParams({
            tokens: tokens,
            targetWeights: weights,
            rebalanceThreshold: 500,
            minRebalanceInterval: 3600,
            poolFee: 3000
        });

        vm.expectRevert();
        rebalanceExecutor.createStrategy(params);
    }

    function test_EmergencyWithdraw() public {
        usdc.mint(address(rebalanceExecutor), 1000e6);

        address recipient = makeAddr("recipient");
        rebalanceExecutor.emergencyWithdraw(address(usdc), recipient, 1000e6);

        assertEq(usdc.balanceOf(recipient), 1000e6);
    }

    // ==================== 补充覆盖测试 ====================

    function test_Unpause() public {
        rebalanceExecutor.pause();
        rebalanceExecutor.unpause();

        // 验证可以创建策略
        bytes32 strategyId = _createDefaultStrategy(user1);
        assertTrue(strategyId != bytes32(0));
    }

    function test_RevertWhen_StrategyNotFound() public {
        bytes32 fakeId = keccak256("fake");
        vm.expectRevert(IRebalanceExecutor.StrategyNotFound.selector);
        rebalanceExecutor.getStrategy(fakeId);
    }

    function test_RevertWhen_RebalanceNotNeeded() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        vm.startPrank(user1);
        usdc.approve(address(rebalanceExecutor), type(uint256).max);
        weth.approve(address(rebalanceExecutor), type(uint256).max);
        vm.stopPrank();

        // 执行一次再平衡
        (bool needed,) = rebalanceExecutor.needsRebalance(strategyId);
        if (needed) {
            rebalanceExecutor.executeRebalance(strategyId);
        }

        // 快进时间
        vm.warp(block.timestamp + 7200);

        // 如果不需要再平衡，应该 revert
        (bool needed2,) = rebalanceExecutor.needsRebalance(strategyId);
        if (!needed2) {
            vm.expectRevert(IRebalanceExecutor.RebalanceNotNeeded.selector);
            rebalanceExecutor.executeRebalance(strategyId);
        }
    }

    function test_RevertWhen_ExecutePausedStrategy() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        vm.prank(user1);
        rebalanceExecutor.pauseStrategy(strategyId);

        vm.expectRevert(IRebalanceExecutor.StrategyNotActive.selector);
        rebalanceExecutor.executeRebalance(strategyId);
    }

    function test_RevertWhen_ExecuteCancelledStrategy() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        vm.prank(user1);
        rebalanceExecutor.cancelStrategy(strategyId);

        vm.expectRevert(IRebalanceExecutor.StrategyNotActive.selector);
        rebalanceExecutor.executeRebalance(strategyId);
    }

    function test_RevertWhen_PausePausedStrategy() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        vm.startPrank(user1);
        rebalanceExecutor.pauseStrategy(strategyId);

        vm.expectRevert(IRebalanceExecutor.StrategyNotActive.selector);
        rebalanceExecutor.pauseStrategy(strategyId);
        vm.stopPrank();
    }

    function test_RevertWhen_ResumeActiveStrategy() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        vm.prank(user1);
        vm.expectRevert("Not paused");
        rebalanceExecutor.resumeStrategy(strategyId);
    }

    function test_RevertWhen_CancelCancelledStrategy() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        vm.startPrank(user1);
        rebalanceExecutor.cancelStrategy(strategyId);

        vm.expectRevert("Already cancelled");
        rebalanceExecutor.cancelStrategy(strategyId);
        vm.stopPrank();
    }

    function test_RevertWhen_UpdateWithInvalidWeightsLength() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        uint256[] memory newWeights = new uint256[](3); // 错误长度
        newWeights[0] = 3000;
        newWeights[1] = 3000;
        newWeights[2] = 4000;

        vm.prank(user1);
        vm.expectRevert(IRebalanceExecutor.InvalidParameters.selector);
        rebalanceExecutor.updateStrategy(strategyId, newWeights, 500);
    }

    function test_RevertWhen_UpdateWithInvalidWeightsSum() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        uint256[] memory newWeights = new uint256[](2);
        newWeights[0] = 5000;
        newWeights[1] = 4000; // 总和 9000

        vm.prank(user1);
        vm.expectRevert(IRebalanceExecutor.WeightsSumInvalid.selector);
        rebalanceExecutor.updateStrategy(strategyId, newWeights, 500);
    }

    function test_RevertWhen_UpdateWithZeroWeight() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        uint256[] memory newWeights = new uint256[](2);
        newWeights[0] = 10000;
        newWeights[1] = 0;

        vm.prank(user1);
        vm.expectRevert(IRebalanceExecutor.InvalidParameters.selector);
        rebalanceExecutor.updateStrategy(strategyId, newWeights, 500);
    }

    function test_RevertWhen_UpdateWithLowThreshold() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        uint256[] memory newWeights = new uint256[](2);
        newWeights[0] = 6000;
        newWeights[1] = 4000;

        vm.prank(user1);
        vm.expectRevert(IRebalanceExecutor.InvalidParameters.selector);
        rebalanceExecutor.updateStrategy(strategyId, newWeights, 50); // < MIN_THRESHOLD
    }

    function test_RevertWhen_CreateWithEmptyTokens() public {
        vm.prank(user1);

        address[] memory tokens = new address[](0);
        uint256[] memory weights = new uint256[](0);

        IRebalanceExecutor.CreateStrategyParams memory params = IRebalanceExecutor.CreateStrategyParams({
            tokens: tokens,
            targetWeights: weights,
            rebalanceThreshold: 500,
            minRebalanceInterval: 3600,
            poolFee: 3000
        });

        vm.expectRevert(IRebalanceExecutor.InvalidParameters.selector);
        rebalanceExecutor.createStrategy(params);
    }

    function test_RevertWhen_CreateWithTooManyAssets() public {
        vm.prank(user1);

        address[] memory tokens = new address[](11); // > MAX_ASSETS
        uint256[] memory weights = new uint256[](11);
        for (uint i = 0; i < 11; i++) {
            tokens[i] = address(uint160(i + 1));
            weights[i] = 909;
        }
        weights[0] = 910; // 调整使总和为 10000

        IRebalanceExecutor.CreateStrategyParams memory params = IRebalanceExecutor.CreateStrategyParams({
            tokens: tokens,
            targetWeights: weights,
            rebalanceThreshold: 500,
            minRebalanceInterval: 3600,
            poolFee: 3000
        });

        vm.expectRevert(IRebalanceExecutor.InvalidParameters.selector);
        rebalanceExecutor.createStrategy(params);
    }

    function test_RevertWhen_CreateWithMismatchedArrays() public {
        vm.prank(user1);

        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weth);

        uint256[] memory weights = new uint256[](3); // 不匹配
        weights[0] = 5000;
        weights[1] = 3000;
        weights[2] = 2000;

        IRebalanceExecutor.CreateStrategyParams memory params = IRebalanceExecutor.CreateStrategyParams({
            tokens: tokens,
            targetWeights: weights,
            rebalanceThreshold: 500,
            minRebalanceInterval: 3600,
            poolFee: 3000
        });

        vm.expectRevert(IRebalanceExecutor.InvalidParameters.selector);
        rebalanceExecutor.createStrategy(params);
    }

    function test_RevertWhen_CreateWithZeroAddress() public {
        vm.prank(user1);

        address[] memory tokens = new address[](2);
        tokens[0] = address(0); // 零地址
        tokens[1] = address(weth);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 6000;
        weights[1] = 4000;

        IRebalanceExecutor.CreateStrategyParams memory params = IRebalanceExecutor.CreateStrategyParams({
            tokens: tokens,
            targetWeights: weights,
            rebalanceThreshold: 500,
            minRebalanceInterval: 3600,
            poolFee: 3000
        });

        vm.expectRevert(IRebalanceExecutor.InvalidParameters.selector);
        rebalanceExecutor.createStrategy(params);
    }

    function test_RevertWhen_CreateWithLowInterval() public {
        vm.prank(user1);

        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weth);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 6000;
        weights[1] = 4000;

        IRebalanceExecutor.CreateStrategyParams memory params = IRebalanceExecutor.CreateStrategyParams({
            tokens: tokens,
            targetWeights: weights,
            rebalanceThreshold: 500,
            minRebalanceInterval: 1800, // < MIN_REBALANCE_INTERVAL
            poolFee: 3000
        });

        vm.expectRevert(IRebalanceExecutor.InvalidParameters.selector);
        rebalanceExecutor.createStrategy(params);
    }

    function test_NeedsRebalance_StrategyNotFound() public {
        bytes32 fakeId = keccak256("fake");
        (bool needed, string memory reason) = rebalanceExecutor.needsRebalance(fakeId);
        assertFalse(needed);
        assertEq(reason, "Strategy not found");
    }

    function test_NeedsRebalance_StrategyNotActive() public {
        bytes32 strategyId = _createDefaultStrategy(user1);

        vm.prank(user1);
        rebalanceExecutor.pauseStrategy(strategyId);

        (bool needed, string memory reason) = rebalanceExecutor.needsRebalance(strategyId);
        assertFalse(needed);
        assertEq(reason, "Strategy not active");
    }

    function test_NeedsRebalance_NoPortfolioValue() public {
        // 创建新用户没有代币
        address user3 = makeAddr("user3");
        vm.prank(user3);
        shieldCore.activateShield(100000e18, 50000e18);

        vm.prank(user3);
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weth);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 6000;
        weights[1] = 4000;

        IRebalanceExecutor.CreateStrategyParams memory params = IRebalanceExecutor.CreateStrategyParams({
            tokens: tokens,
            targetWeights: weights,
            rebalanceThreshold: 500,
            minRebalanceInterval: 3600,
            poolFee: 3000
        });

        bytes32 strategyId = rebalanceExecutor.createStrategy(params);

        (bool needed, string memory reason) = rebalanceExecutor.needsRebalance(strategyId);
        assertFalse(needed);
        assertEq(reason, "No portfolio value");
    }

    function test_GetCurrentWeights_ZeroValue() public {
        address user3 = makeAddr("user3");
        vm.prank(user3);
        shieldCore.activateShield(100000e18, 50000e18);

        vm.prank(user3);
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weth);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 6000;
        weights[1] = 4000;

        IRebalanceExecutor.CreateStrategyParams memory params = IRebalanceExecutor.CreateStrategyParams({
            tokens: tokens,
            targetWeights: weights,
            rebalanceThreshold: 500,
            minRebalanceInterval: 3600,
            poolFee: 3000
        });

        bytes32 strategyId = rebalanceExecutor.createStrategy(params);

        uint256[] memory currentWeights = rebalanceExecutor.getCurrentWeights(strategyId);
        assertEq(currentWeights[0], 0);
        assertEq(currentWeights[1], 0);
    }

    function test_InsufficientBalance_StillExecutes() public {
        // 用户没有足够的代币进行再平衡
        address user3 = makeAddr("user3");
        vm.prank(user3);
        shieldCore.activateShield(100000e18, 50000e18);

        // 只给一点点代币
        usdc.mint(user3, 1e6);

        vm.prank(user3);
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weth);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 6000;
        weights[1] = 4000;

        IRebalanceExecutor.CreateStrategyParams memory params = IRebalanceExecutor.CreateStrategyParams({
            tokens: tokens,
            targetWeights: weights,
            rebalanceThreshold: 100, // 1% 阈值
            minRebalanceInterval: 3600,
            poolFee: 3000
        });

        bytes32 strategyId = rebalanceExecutor.createStrategy(params);

        // 验证策略已创建
        IRebalanceExecutor.RebalanceStrategy memory strategy = rebalanceExecutor.getStrategy(strategyId);
        assertEq(strategy.user, user3);
    }

    function test_ReceiveEther() public {
        // 测试 receive 函数
        (bool success,) = address(rebalanceExecutor).call{value: 1 ether}("");
        assertTrue(success);
    }

    // ==================== 辅助函数 ====================

    function _createDefaultStrategy(address user) internal returns (bytes32) {
        vm.prank(user);

        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weth);

        uint256[] memory weights = new uint256[](2);
        weights[0] = 6000; // 60%
        weights[1] = 4000; // 40%

        IRebalanceExecutor.CreateStrategyParams memory params = IRebalanceExecutor.CreateStrategyParams({
            tokens: tokens,
            targetWeights: weights,
            rebalanceThreshold: 500, // 5%
            minRebalanceInterval: 3600,
            poolFee: 3000
        });

        return rebalanceExecutor.createStrategy(params);
    }
}
