// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IStopLossExecutor} from "../interfaces/IStopLossExecutor.sol";
import {IShieldCore} from "../interfaces/IShieldCore.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

// Uniswap V3 接口
interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

// 价格预言机接口
interface IPriceOracle {
    function getPrice(address token) external view returns (uint256 price);
}

/**
 * @title StopLossExecutor
 * @author Shield Protocol Team
 * @notice 止损保护策略执行合约
 * @dev 实现了自动化止损保护功能
 *
 * 核心功能:
 * 1. 固定价格止损: 当价格跌到指定价格时触发
 * 2. 百分比止损: 当价格跌幅超过指定百分比时触发
 * 3. 追踪止损: 跟随价格上涨，在回调时触发
 * 4. 与 ShieldCore 集成进行限额检查
 *
 * 执行流程:
 * 1. 用户创建止损策略
 * 2. Keeper 定期检查价格是否触发止损
 * 3. 如果触发，自动卖出代币保护资产
 */
contract StopLossExecutor is IStopLossExecutor, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============ 常量 ============

    /// @notice 百分比基数 (100% = 10000)
    uint256 public constant PERCENTAGE_BASE = 10000;

    /// @notice 最小止损百分比 (1%)
    uint256 public constant MIN_STOP_PERCENTAGE = 100;

    /// @notice 最大止损百分比 (50%)
    uint256 public constant MAX_STOP_PERCENTAGE = 5000;

    /// @notice 交易超时时间
    uint256 public constant SWAP_DEADLINE = 300; // 5 分钟

    // ============ 不可变量 ============

    /// @notice Shield 核心合约
    IShieldCore public immutable shieldCore;

    /// @notice Uniswap V3 路由合约
    ISwapRouter public immutable swapRouter;

    /// @notice 价格预言机
    IPriceOracle public priceOracle;

    // ============ 状态变量 ============

    /// @notice 策略 ID => 策略详情
    mapping(bytes32 => StopLossStrategy) private _strategies;

    /// @notice 用户地址 => 策略 ID 数组
    mapping(address => bytes32[]) private _userStrategies;

    /// @notice 策略 ID => 执行记录数组
    mapping(bytes32 => ExecutionRecord[]) private _executionHistory;

    /// @notice 所有策略 ID 列表
    bytes32[] private _allStrategyIds;

    /// @notice 协议手续费 (基点)
    uint256 public protocolFeeBps;

    /// @notice 手续费接收地址
    address public feeRecipient;

    // ============ 修饰符 ============

    modifier onlyStrategyOwner(bytes32 strategyId) {
        if (_strategies[strategyId].user != msg.sender) {
            revert NotStrategyOwner();
        }
        _;
    }

    modifier strategyExists(bytes32 strategyId) {
        if (_strategies[strategyId].user == address(0)) {
            revert StrategyNotFound();
        }
        _;
    }

    // ============ 构造函数 ============

    constructor(
        address _shieldCore,
        address _swapRouter,
        address _priceOracle
    ) Ownable(msg.sender) {
        require(_shieldCore != address(0), "Invalid ShieldCore");
        require(_swapRouter != address(0), "Invalid SwapRouter");
        require(_priceOracle != address(0), "Invalid PriceOracle");

        shieldCore = IShieldCore(_shieldCore);
        swapRouter = ISwapRouter(_swapRouter);
        priceOracle = IPriceOracle(_priceOracle);

        feeRecipient = msg.sender;
        protocolFeeBps = 30; // 0.3% 默认手续费
    }

    // ============ 管理函数 ============

    function setProtocolFee(uint256 feeBps) external onlyOwner {
        require(feeBps <= 100, "Fee too high");
        protocolFeeBps = feeBps;
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        feeRecipient = recipient;
    }

    function setPriceOracle(address _priceOracle) external onlyOwner {
        require(_priceOracle != address(0), "Invalid oracle");
        priceOracle = IPriceOracle(_priceOracle);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ 策略管理函数 ============

    /**
     * @notice 创建止损策略
     * @param params 策略参数
     * @return strategyId 策略 ID
     */
    function createStrategy(
        CreateStrategyParams calldata params
    ) external whenNotPaused nonReentrant returns (bytes32 strategyId) {
        // 参数验证
        if (params.tokenToSell == address(0)) revert InvalidParameters();
        if (params.tokenToReceive == address(0)) revert InvalidParameters();
        if (params.tokenToSell == params.tokenToReceive) revert InvalidParameters();
        if (params.amount == 0) revert InvalidParameters();

        // 验证止损参数
        if (params.stopLossType == StopLossType.Percentage) {
            if (params.triggerValue < MIN_STOP_PERCENTAGE) revert InvalidParameters();
            if (params.triggerValue > MAX_STOP_PERCENTAGE) revert InvalidParameters();
        } else if (params.stopLossType == StopLossType.TrailingStop) {
            if (params.trailingDistance < MIN_STOP_PERCENTAGE) revert InvalidParameters();
            if (params.trailingDistance > MAX_STOP_PERCENTAGE) revert InvalidParameters();
        } else {
            // FixedPrice
            if (params.triggerValue == 0) revert InvalidParameters();
        }

        // 生成唯一策略 ID
        strategyId = keccak256(abi.encodePacked(
            msg.sender,
            params.tokenToSell,
            params.tokenToReceive,
            params.amount,
            block.timestamp,
            block.number
        ));

        require(_strategies[strategyId].user == address(0), "Strategy ID collision");

        // 获取当前价格
        uint256 currentPrice = priceOracle.getPrice(params.tokenToSell);

        // 计算触发价格
        uint256 triggerPrice;
        if (params.stopLossType == StopLossType.FixedPrice) {
            triggerPrice = params.triggerValue;
        } else if (params.stopLossType == StopLossType.Percentage) {
            // 百分比止损: 当前价格 * (1 - 百分比)
            triggerPrice = (currentPrice * (PERCENTAGE_BASE - params.triggerValue)) / PERCENTAGE_BASE;
        } else {
            // 追踪止损: 初始触发价格
            triggerPrice = (currentPrice * (PERCENTAGE_BASE - params.trailingDistance)) / PERCENTAGE_BASE;
        }

        // 创建策略
        _strategies[strategyId] = StopLossStrategy({
            user: msg.sender,
            tokenToSell: params.tokenToSell,
            tokenToReceive: params.tokenToReceive,
            amount: params.amount,
            stopLossType: params.stopLossType,
            triggerPrice: triggerPrice,
            triggerPercentage: params.stopLossType == StopLossType.Percentage ? params.triggerValue : 0,
            trailingDistance: params.trailingDistance,
            highestPrice: currentPrice,
            minAmountOut: params.minAmountOut,
            poolFee: params.poolFee,
            status: StrategyStatus.Active,
            createdAt: block.timestamp,
            triggeredAt: 0,
            executedAmount: 0
        });

        // 记录用户策略
        _userStrategies[msg.sender].push(strategyId);
        _allStrategyIds.push(strategyId);

        emit StrategyCreated(
            strategyId,
            msg.sender,
            params.tokenToSell,
            params.tokenToReceive,
            params.amount,
            params.stopLossType,
            params.triggerValue
        );
    }

    /**
     * @notice 检查并执行止损
     * @param strategyId 策略 ID
     * @return executed 是否执行
     */
    function checkAndExecute(
        bytes32 strategyId
    ) external strategyExists(strategyId) whenNotPaused nonReentrant returns (bool executed) {
        StopLossStrategy storage strategy = _strategies[strategyId];

        // 检查状态
        if (strategy.status != StrategyStatus.Active) {
            return false;
        }

        // 获取当前价格
        uint256 currentPrice = priceOracle.getPrice(strategy.tokenToSell);

        // 更新追踪止损的最高价
        if (strategy.stopLossType == StopLossType.TrailingStop) {
            if (currentPrice > strategy.highestPrice) {
                uint256 oldHighest = strategy.highestPrice;
                strategy.highestPrice = currentPrice;
                strategy.triggerPrice = (currentPrice * (PERCENTAGE_BASE - strategy.trailingDistance)) / PERCENTAGE_BASE;

                emit HighestPriceUpdated(strategyId, oldHighest, currentPrice);
            }
        }

        // 检查是否应该触发
        (bool triggered,) = shouldTrigger(strategyId);
        if (!triggered) {
            return false;
        }

        // 执行止损
        _executeStopLoss(strategyId, currentPrice);

        return true;
    }

    /**
     * @notice 批量检查并执行
     */
    function batchCheckAndExecute(
        bytes32[] calldata strategyIds
    ) external whenNotPaused nonReentrant returns (uint256 executedCount) {
        for (uint256 i = 0; i < strategyIds.length; i++) {
            try this.checkAndExecuteInternal(strategyIds[i]) returns (bool executed) {
                if (executed) executedCount++;
            } catch {
                // 忽略失败
            }
        }
    }

    /// @notice 内部执行函数 (用于批量执行)
    function checkAndExecuteInternal(bytes32 strategyId) external returns (bool) {
        require(msg.sender == address(this), "Only internal");
        return _checkAndExecuteInternal(strategyId);
    }

    function _checkAndExecuteInternal(bytes32 strategyId) internal returns (bool) {
        StopLossStrategy storage strategy = _strategies[strategyId];

        if (strategy.user == address(0) || strategy.status != StrategyStatus.Active) {
            return false;
        }

        uint256 currentPrice = priceOracle.getPrice(strategy.tokenToSell);

        // 更新追踪止损
        if (strategy.stopLossType == StopLossType.TrailingStop && currentPrice > strategy.highestPrice) {
            strategy.highestPrice = currentPrice;
            strategy.triggerPrice = (currentPrice * (PERCENTAGE_BASE - strategy.trailingDistance)) / PERCENTAGE_BASE;
        }

        if (currentPrice <= strategy.triggerPrice) {
            _executeStopLoss(strategyId, currentPrice);
            return true;
        }

        return false;
    }

    /**
     * @notice 执行止损
     */
    function _executeStopLoss(bytes32 strategyId, uint256 currentPrice) internal {
        StopLossStrategy storage strategy = _strategies[strategyId];

        // 记录触发
        emit StopLossTriggered(
            strategyId,
            strategy.user,
            currentPrice,
            strategy.triggerPrice,
            block.timestamp
        );

        // 检查用户余额
        uint256 userBalance = IERC20(strategy.tokenToSell).balanceOf(strategy.user);
        uint256 amountToSell = userBalance < strategy.amount ? userBalance : strategy.amount;

        if (amountToSell == 0) {
            strategy.status = StrategyStatus.Triggered;
            strategy.triggeredAt = block.timestamp;
            return;
        }

        // 检查 Shield 限额
        shieldCore.recordSpending(strategy.user, strategy.tokenToSell, amountToSell);

        // 从用户账户转入代币
        IERC20(strategy.tokenToSell).safeTransferFrom(
            strategy.user,
            address(this),
            amountToSell
        );

        // 计算手续费
        uint256 feeAmount = (amountToSell * protocolFeeBps) / 10000;
        uint256 swapAmount = amountToSell - feeAmount;

        // 转移手续费
        if (feeAmount > 0 && feeRecipient != address(0)) {
            IERC20(strategy.tokenToSell).safeTransfer(feeRecipient, feeAmount);
        }

        // 执行兑换
        IERC20(strategy.tokenToSell).forceApprove(address(swapRouter), swapAmount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: strategy.tokenToSell,
            tokenOut: strategy.tokenToReceive,
            fee: strategy.poolFee,
            recipient: strategy.user,
            deadline: block.timestamp + SWAP_DEADLINE,
            amountIn: swapAmount,
            amountOutMinimum: strategy.minAmountOut,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = swapRouter.exactInputSingle(params);

        // 检查滑点
        if (amountOut < strategy.minAmountOut) {
            revert SlippageExceeded(strategy.minAmountOut, amountOut);
        }

        // 计算执行价格
        uint256 executionPrice = (amountToSell * 1e18) / amountOut;

        // 更新策略状态
        strategy.status = StrategyStatus.Triggered;
        strategy.triggeredAt = block.timestamp;
        strategy.executedAmount = amountToSell;

        // 记录执行历史
        _executionHistory[strategyId].push(ExecutionRecord({
            strategyId: strategyId,
            amountSold: amountToSell,
            amountReceived: amountOut,
            executionPrice: executionPrice,
            timestamp: block.timestamp
        }));

        emit StopLossExecuted(
            strategyId,
            strategy.user,
            amountToSell,
            amountOut,
            executionPrice,
            block.timestamp
        );
    }

    /**
     * @notice 更新最高价 (追踪止损)
     */
    function updateHighestPrice(
        bytes32 strategyId,
        uint256 currentPrice
    ) external strategyExists(strategyId) {
        StopLossStrategy storage strategy = _strategies[strategyId];

        if (strategy.stopLossType != StopLossType.TrailingStop) {
            revert InvalidParameters();
        }

        if (strategy.status != StrategyStatus.Active) {
            revert StrategyNotActive();
        }

        if (currentPrice > strategy.highestPrice) {
            uint256 oldHighest = strategy.highestPrice;
            strategy.highestPrice = currentPrice;
            strategy.triggerPrice = (currentPrice * (PERCENTAGE_BASE - strategy.trailingDistance)) / PERCENTAGE_BASE;

            emit HighestPriceUpdated(strategyId, oldHighest, currentPrice);
        }
    }

    /**
     * @notice 暂停策略
     */
    function pauseStrategy(
        bytes32 strategyId
    ) external strategyExists(strategyId) onlyStrategyOwner(strategyId) {
        StopLossStrategy storage strategy = _strategies[strategyId];

        if (strategy.status != StrategyStatus.Active) {
            revert StrategyNotActive();
        }

        strategy.status = StrategyStatus.Paused;

        emit StrategyPaused(strategyId, block.timestamp);
    }

    /**
     * @notice 恢复策略
     */
    function resumeStrategy(
        bytes32 strategyId
    ) external strategyExists(strategyId) onlyStrategyOwner(strategyId) {
        StopLossStrategy storage strategy = _strategies[strategyId];

        require(strategy.status == StrategyStatus.Paused, "Not paused");

        strategy.status = StrategyStatus.Active;
        // 重新获取当前价格更新最高价
        uint256 currentPrice = priceOracle.getPrice(strategy.tokenToSell);
        if (strategy.stopLossType == StopLossType.TrailingStop) {
            strategy.highestPrice = currentPrice;
            strategy.triggerPrice = (currentPrice * (PERCENTAGE_BASE - strategy.trailingDistance)) / PERCENTAGE_BASE;
        }

        emit StrategyResumed(strategyId, block.timestamp);
    }

    /**
     * @notice 取消策略
     */
    function cancelStrategy(
        bytes32 strategyId
    ) external strategyExists(strategyId) onlyStrategyOwner(strategyId) {
        StopLossStrategy storage strategy = _strategies[strategyId];

        require(strategy.status != StrategyStatus.Cancelled, "Already cancelled");
        require(strategy.status != StrategyStatus.Triggered, "Already triggered");

        strategy.status = StrategyStatus.Cancelled;

        emit StrategyCancelled(strategyId, block.timestamp);
    }

    /**
     * @notice 更新策略参数
     */
    function updateStrategy(
        bytes32 strategyId,
        uint256 newTriggerValue,
        uint256 newMinAmountOut
    ) external strategyExists(strategyId) onlyStrategyOwner(strategyId) {
        StopLossStrategy storage strategy = _strategies[strategyId];

        if (strategy.status != StrategyStatus.Active) {
            revert StrategyNotActive();
        }

        // 更新触发价格
        if (strategy.stopLossType == StopLossType.FixedPrice) {
            if (newTriggerValue == 0) revert InvalidParameters();
            strategy.triggerPrice = newTriggerValue;
        } else if (strategy.stopLossType == StopLossType.Percentage) {
            if (newTriggerValue < MIN_STOP_PERCENTAGE || newTriggerValue > MAX_STOP_PERCENTAGE) {
                revert InvalidParameters();
            }
            strategy.triggerPercentage = newTriggerValue;
            uint256 currentPrice = priceOracle.getPrice(strategy.tokenToSell);
            strategy.triggerPrice = (currentPrice * (PERCENTAGE_BASE - newTriggerValue)) / PERCENTAGE_BASE;
        } else {
            // TrailingStop
            if (newTriggerValue < MIN_STOP_PERCENTAGE || newTriggerValue > MAX_STOP_PERCENTAGE) {
                revert InvalidParameters();
            }
            strategy.trailingDistance = newTriggerValue;
            strategy.triggerPrice = (strategy.highestPrice * (PERCENTAGE_BASE - newTriggerValue)) / PERCENTAGE_BASE;
        }

        strategy.minAmountOut = newMinAmountOut;

        emit StrategyUpdated(strategyId, newTriggerValue, newMinAmountOut);
    }

    // ============ 视图函数 ============

    /**
     * @notice 获取策略详情
     */
    function getStrategy(
        bytes32 strategyId
    ) external view strategyExists(strategyId) returns (StopLossStrategy memory) {
        return _strategies[strategyId];
    }

    /**
     * @notice 获取用户的所有策略 ID
     */
    function getUserStrategies(address user) external view returns (bytes32[] memory) {
        return _userStrategies[user];
    }

    /**
     * @notice 检查止损是否应该触发
     */
    function shouldTrigger(
        bytes32 strategyId
    ) public view returns (bool triggered, uint256 currentPrice) {
        StopLossStrategy memory strategy = _strategies[strategyId];

        if (strategy.user == address(0)) {
            return (false, 0);
        }

        if (strategy.status != StrategyStatus.Active) {
            return (false, 0);
        }

        currentPrice = priceOracle.getPrice(strategy.tokenToSell);

        // 检查价格是否触发止损
        triggered = currentPrice <= strategy.triggerPrice;
    }

    /**
     * @notice 获取当前触发价格
     */
    function getCurrentTriggerPrice(bytes32 strategyId) external view returns (uint256) {
        return _strategies[strategyId].triggerPrice;
    }

    /**
     * @notice 获取待触发的策略
     */
    function getPendingStrategies(
        uint256 limit
    ) external view returns (bytes32[] memory strategyIds) {
        uint256 count = 0;
        uint256 maxLen = limit > _allStrategyIds.length ? _allStrategyIds.length : limit;
        bytes32[] memory temp = new bytes32[](maxLen);

        for (uint256 i = 0; i < _allStrategyIds.length && count < maxLen; i++) {
            bytes32 sid = _allStrategyIds[i];
            StopLossStrategy memory strategy = _strategies[sid];

            if (strategy.status == StrategyStatus.Active) {
                uint256 currentPrice = priceOracle.getPrice(strategy.tokenToSell);
                if (currentPrice <= strategy.triggerPrice) {
                    temp[count] = sid;
                    count++;
                }
            }
        }

        strategyIds = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            strategyIds[i] = temp[i];
        }
    }

    /**
     * @notice 获取执行历史
     */
    function getExecutionHistory(
        bytes32 strategyId
    ) external view returns (ExecutionRecord[] memory) {
        return _executionHistory[strategyId];
    }

    // ============ 紧急函数 ============

    /**
     * @notice 紧急提取卡住的代币
     */
    function emergencyWithdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    receive() external payable {}
}
