// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRebalanceExecutor} from "../interfaces/IRebalanceExecutor.sol";
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
 * @title RebalanceExecutor
 * @author Shield Protocol Team
 * @notice 投资组合再平衡策略执行合约
 * @dev 实现了自动化投资组合再平衡功能
 *
 * 核心功能:
 * 1. 创建再平衡策略 (指定代币和目标权重)
 * 2. 检测投资组合偏离并自动再平衡
 * 3. 与 ShieldCore 集成进行限额检查
 * 4. 使用 Uniswap V3 执行实际兑换
 *
 * 执行流程:
 * 1. 用户创建策略，设置目标权重和阈值
 * 2. Keeper 定期检查是否需要再平衡
 * 3. 如果偏离超过阈值，执行再平衡
 * 4. 卖出超配资产，买入欠配资产
 */
contract RebalanceExecutor is IRebalanceExecutor, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============ 常量 ============

    /// @notice 权重总和 (100% = 10000 基点)
    uint256 public constant TOTAL_WEIGHT = 10000;

    /// @notice 最小再平衡间隔 (1 小时)
    uint256 public constant MIN_REBALANCE_INTERVAL = 3600;

    /// @notice 最大资产数量
    uint256 public constant MAX_ASSETS = 10;

    /// @notice 最小阈值 (1%)
    uint256 public constant MIN_THRESHOLD = 100;

    /// @notice 交易超时时间
    uint256 public constant SWAP_DEADLINE = 300; // 5 分钟

    // ============ 不可变量 ============

    /// @notice Shield 核心合约
    IShieldCore public immutable shieldCore;

    /// @notice Uniswap V3 路由合约
    ISwapRouter public immutable swapRouter;

    /// @notice 价格预言机
    IPriceOracle public priceOracle;

    /// @notice 基础报价代币 (如 USDC)
    address public immutable quoteToken;

    // ============ 状态变量 ============

    /// @notice 策略 ID => 策略所有者
    mapping(bytes32 => address) private _strategyOwners;

    /// @notice 策略 ID => 资产配置
    mapping(bytes32 => AssetAllocation[]) private _strategyAllocations;

    /// @notice 策略 ID => 策略元数据
    struct StrategyMetadata {
        uint256 rebalanceThreshold;
        uint256 minRebalanceInterval;
        uint256 lastRebalanceTime;
        uint256 totalRebalances;
        uint24 poolFee;
        StrategyStatus status;
        uint256 createdAt;
        uint256 updatedAt;
    }
    mapping(bytes32 => StrategyMetadata) private _strategyMetadata;

    /// @notice 用户地址 => 策略 ID 数组
    mapping(address => bytes32[]) private _userStrategies;

    /// @notice 策略 ID => 再平衡记录数组
    mapping(bytes32 => RebalanceRecord[]) private _rebalanceHistory;

    /// @notice 所有策略 ID 列表
    bytes32[] private _allStrategyIds;

    /// @notice 协议手续费 (基点)
    uint256 public protocolFeeBps;

    /// @notice 手续费接收地址
    address public feeRecipient;

    // ============ 修饰符 ============

    modifier onlyStrategyOwner(bytes32 strategyId) {
        if (_strategyOwners[strategyId] != msg.sender) {
            revert NotStrategyOwner();
        }
        _;
    }

    modifier strategyExists(bytes32 strategyId) {
        if (_strategyOwners[strategyId] == address(0)) {
            revert StrategyNotFound();
        }
        _;
    }

    // ============ 构造函数 ============

    constructor(
        address _shieldCore,
        address _swapRouter,
        address _priceOracle,
        address _quoteToken
    ) Ownable(msg.sender) {
        require(_shieldCore != address(0), "Invalid ShieldCore");
        require(_swapRouter != address(0), "Invalid SwapRouter");
        require(_priceOracle != address(0), "Invalid PriceOracle");
        require(_quoteToken != address(0), "Invalid QuoteToken");

        shieldCore = IShieldCore(_shieldCore);
        swapRouter = ISwapRouter(_swapRouter);
        priceOracle = IPriceOracle(_priceOracle);
        quoteToken = _quoteToken;

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
     * @notice 创建再平衡策略
     * @param params 策略参数
     * @return strategyId 策略 ID
     */
    function createStrategy(
        CreateStrategyParams calldata params
    ) external whenNotPaused nonReentrant returns (bytes32 strategyId) {
        // 参数验证
        if (params.tokens.length == 0) revert InvalidParameters();
        if (params.tokens.length > MAX_ASSETS) revert InvalidParameters();
        if (params.tokens.length != params.targetWeights.length) revert InvalidParameters();
        if (params.rebalanceThreshold < MIN_THRESHOLD) revert InvalidParameters();
        if (params.minRebalanceInterval < MIN_REBALANCE_INTERVAL) revert InvalidParameters();

        // 验证权重总和
        uint256 totalWeight;
        for (uint256 i = 0; i < params.targetWeights.length; i++) {
            if (params.tokens[i] == address(0)) revert InvalidParameters();
            if (params.targetWeights[i] == 0) revert InvalidParameters();
            totalWeight += params.targetWeights[i];
        }
        if (totalWeight != TOTAL_WEIGHT) revert WeightsSumInvalid();

        // 生成唯一策略 ID
        strategyId = keccak256(abi.encodePacked(
            msg.sender,
            params.tokens[0],
            params.tokens.length,
            block.timestamp,
            block.number
        ));

        require(_strategyOwners[strategyId] == address(0), "Strategy ID collision");

        // 存储策略所有者
        _strategyOwners[strategyId] = msg.sender;

        // 存储资产配置
        for (uint256 i = 0; i < params.tokens.length; i++) {
            _strategyAllocations[strategyId].push(AssetAllocation({
                token: params.tokens[i],
                targetWeight: params.targetWeights[i],
                currentWeight: 0
            }));
        }

        // 存储策略元数据
        _strategyMetadata[strategyId] = StrategyMetadata({
            rebalanceThreshold: params.rebalanceThreshold,
            minRebalanceInterval: params.minRebalanceInterval,
            lastRebalanceTime: 0,
            totalRebalances: 0,
            poolFee: params.poolFee,
            status: StrategyStatus.Active,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        // 记录用户策略
        _userStrategies[msg.sender].push(strategyId);
        _allStrategyIds.push(strategyId);

        emit StrategyCreated(
            strategyId,
            msg.sender,
            params.tokens,
            params.targetWeights,
            params.rebalanceThreshold
        );
    }

    /**
     * @notice 执行再平衡
     * @param strategyId 策略 ID
     */
    function executeRebalance(
        bytes32 strategyId
    ) external strategyExists(strategyId) whenNotPaused nonReentrant {
        StrategyMetadata storage metadata = _strategyMetadata[strategyId];

        // 检查策略状态
        if (metadata.status != StrategyStatus.Active) {
            revert StrategyNotActive();
        }

        // 检查再平衡间隔
        if (metadata.lastRebalanceTime > 0 &&
            block.timestamp < metadata.lastRebalanceTime + metadata.minRebalanceInterval) {
            revert RebalanceTooSoon(metadata.lastRebalanceTime + metadata.minRebalanceInterval);
        }

        // 检查是否需要再平衡
        (bool needed,) = needsRebalance(strategyId);
        if (!needed) {
            revert RebalanceNotNeeded();
        }

        address user = _strategyOwners[strategyId];
        AssetAllocation[] storage allocations = _strategyAllocations[strategyId];

        // 计算总价值和当前权重
        uint256 totalValue = _calculatePortfolioValue(user, allocations);
        if (totalValue == 0) revert InsufficientBalance();

        // 计算每个资产需要的调整
        _executeRebalanceTrades(strategyId, user, allocations, totalValue, metadata.poolFee);

        // 更新状态
        metadata.lastRebalanceTime = block.timestamp;
        metadata.totalRebalances++;
        metadata.updatedAt = block.timestamp;

        // 记录再平衡历史
        _rebalanceHistory[strategyId].push(RebalanceRecord({
            strategyId: strategyId,
            timestamp: block.timestamp,
            totalValueBefore: totalValue,
            totalValueAfter: _calculatePortfolioValue(user, allocations),
            gasUsed: 0
        }));

        emit RebalanceExecuted(
            strategyId,
            user,
            totalValue,
            metadata.totalRebalances,
            block.timestamp
        );
    }

    /**
     * @notice 执行再平衡交易
     */
    function _executeRebalanceTrades(
        bytes32 strategyId,
        address user,
        AssetAllocation[] storage allocations,
        uint256 totalValue,
        uint24 poolFee
    ) internal {
        uint256 assetCount = allocations.length;

        // 计算每个资产的目标价值和当前价值
        int256[] memory deltas = new int256[](assetCount);

        for (uint256 i = 0; i < assetCount; i++) {
            uint256 targetValue = (totalValue * allocations[i].targetWeight) / TOTAL_WEIGHT;
            uint256 currentValue = _getAssetValue(user, allocations[i].token);
            deltas[i] = int256(targetValue) - int256(currentValue);
        }

        // 先卖出超配的资产 (delta < 0)
        for (uint256 i = 0; i < assetCount; i++) {
            if (deltas[i] < 0) {
                uint256 sellValue = uint256(-deltas[i]);
                uint256 price = priceOracle.getPrice(allocations[i].token);
                uint256 sellAmount = (sellValue * 1e18) / price;

                // 检查 Shield 限额
                shieldCore.recordSpending(user, allocations[i].token, sellAmount);

                // 执行卖出
                _executeSell(user, allocations[i].token, sellAmount, poolFee);
            }
        }

        // 再买入欠配的资产 (delta > 0)
        for (uint256 i = 0; i < assetCount; i++) {
            if (deltas[i] > 0) {
                uint256 buyValue = uint256(deltas[i]);

                // 执行买入
                _executeBuy(user, allocations[i].token, buyValue, poolFee);
            }
        }
    }

    /**
     * @notice 执行卖出操作
     */
    function _executeSell(
        address user,
        address tokenToSell,
        uint256 amount,
        uint24 poolFee
    ) internal {
        // 从用户账户转入代币
        IERC20(tokenToSell).safeTransferFrom(user, address(this), amount);

        // 计算手续费
        uint256 feeAmount = (amount * protocolFeeBps) / 10000;
        uint256 swapAmount = amount - feeAmount;

        // 转移手续费
        if (feeAmount > 0 && feeRecipient != address(0)) {
            IERC20(tokenToSell).safeTransfer(feeRecipient, feeAmount);
        }

        // 如果不是报价代币，执行兑换
        if (tokenToSell != quoteToken) {
            IERC20(tokenToSell).forceApprove(address(swapRouter), swapAmount);

            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenToSell,
                tokenOut: quoteToken,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp + SWAP_DEADLINE,
                amountIn: swapAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            swapRouter.exactInputSingle(params);
        }
    }

    /**
     * @notice 执行买入操作
     */
    function _executeBuy(
        address user,
        address tokenToBuy,
        uint256 buyValue,
        uint24 poolFee
    ) internal {
        if (tokenToBuy == quoteToken) {
            // 直接转给用户
            uint256 balance = IERC20(quoteToken).balanceOf(address(this));
            if (balance > 0) {
                uint256 transferAmount = balance < buyValue ? balance : buyValue;
                IERC20(quoteToken).safeTransfer(user, transferAmount);
            }
        } else {
            // 使用 quoteToken 买入目标代币
            uint256 quoteBalance = IERC20(quoteToken).balanceOf(address(this));
            uint256 amountIn = quoteBalance < buyValue ? quoteBalance : buyValue;

            if (amountIn > 0) {
                IERC20(quoteToken).forceApprove(address(swapRouter), amountIn);

                ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                    tokenIn: quoteToken,
                    tokenOut: tokenToBuy,
                    fee: poolFee,
                    recipient: user,
                    deadline: block.timestamp + SWAP_DEADLINE,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                });

                swapRouter.exactInputSingle(params);
            }
        }
    }

    /**
     * @notice 暂停策略
     */
    function pauseStrategy(
        bytes32 strategyId
    ) external strategyExists(strategyId) onlyStrategyOwner(strategyId) {
        StrategyMetadata storage metadata = _strategyMetadata[strategyId];

        if (metadata.status != StrategyStatus.Active) {
            revert StrategyNotActive();
        }

        metadata.status = StrategyStatus.Paused;
        metadata.updatedAt = block.timestamp;

        emit StrategyPaused(strategyId, block.timestamp);
    }

    /**
     * @notice 恢复策略
     */
    function resumeStrategy(
        bytes32 strategyId
    ) external strategyExists(strategyId) onlyStrategyOwner(strategyId) {
        StrategyMetadata storage metadata = _strategyMetadata[strategyId];

        require(metadata.status == StrategyStatus.Paused, "Not paused");

        metadata.status = StrategyStatus.Active;
        metadata.updatedAt = block.timestamp;

        emit StrategyResumed(strategyId, block.timestamp);
    }

    /**
     * @notice 取消策略
     */
    function cancelStrategy(
        bytes32 strategyId
    ) external strategyExists(strategyId) onlyStrategyOwner(strategyId) {
        StrategyMetadata storage metadata = _strategyMetadata[strategyId];

        require(metadata.status != StrategyStatus.Cancelled, "Already cancelled");

        metadata.status = StrategyStatus.Cancelled;
        metadata.updatedAt = block.timestamp;

        emit StrategyCancelled(strategyId, block.timestamp);
    }

    /**
     * @notice 更新策略参数
     */
    function updateStrategy(
        bytes32 strategyId,
        uint256[] calldata newTargetWeights,
        uint256 newThreshold
    ) external strategyExists(strategyId) onlyStrategyOwner(strategyId) {
        AssetAllocation[] storage allocations = _strategyAllocations[strategyId];

        if (newTargetWeights.length != allocations.length) revert InvalidParameters();
        if (newThreshold < MIN_THRESHOLD) revert InvalidParameters();

        // 验证权重总和
        uint256 totalWeight;
        for (uint256 i = 0; i < newTargetWeights.length; i++) {
            if (newTargetWeights[i] == 0) revert InvalidParameters();
            totalWeight += newTargetWeights[i];
        }
        if (totalWeight != TOTAL_WEIGHT) revert WeightsSumInvalid();

        // 更新权重
        for (uint256 i = 0; i < allocations.length; i++) {
            allocations[i].targetWeight = newTargetWeights[i];
        }

        StrategyMetadata storage metadata = _strategyMetadata[strategyId];
        metadata.rebalanceThreshold = newThreshold;
        metadata.updatedAt = block.timestamp;

        emit StrategyUpdated(strategyId, newTargetWeights, newThreshold);
    }

    // ============ 视图函数 ============

    /**
     * @notice 获取策略详情
     */
    function getStrategy(
        bytes32 strategyId
    ) external view strategyExists(strategyId) returns (RebalanceStrategy memory strategy) {
        address owner = _strategyOwners[strategyId];
        AssetAllocation[] memory allocations = _strategyAllocations[strategyId];
        StrategyMetadata memory metadata = _strategyMetadata[strategyId];

        // 更新当前权重
        uint256 totalValue = _calculatePortfolioValue(owner, allocations);
        if (totalValue > 0) {
            for (uint256 i = 0; i < allocations.length; i++) {
                uint256 assetValue = _getAssetValue(owner, allocations[i].token);
                allocations[i].currentWeight = (assetValue * TOTAL_WEIGHT) / totalValue;
            }
        }

        strategy = RebalanceStrategy({
            user: owner,
            allocations: allocations,
            rebalanceThreshold: metadata.rebalanceThreshold,
            minRebalanceInterval: metadata.minRebalanceInterval,
            lastRebalanceTime: metadata.lastRebalanceTime,
            totalRebalances: metadata.totalRebalances,
            poolFee: metadata.poolFee,
            status: metadata.status,
            createdAt: metadata.createdAt,
            updatedAt: metadata.updatedAt
        });
    }

    /**
     * @notice 获取用户的所有策略 ID
     */
    function getUserStrategies(address user) external view returns (bytes32[] memory) {
        return _userStrategies[user];
    }

    /**
     * @notice 检查是否需要再平衡
     */
    function needsRebalance(
        bytes32 strategyId
    ) public view returns (bool needed, string memory reason) {
        if (_strategyOwners[strategyId] == address(0)) {
            return (false, "Strategy not found");
        }

        StrategyMetadata memory metadata = _strategyMetadata[strategyId];

        if (metadata.status != StrategyStatus.Active) {
            return (false, "Strategy not active");
        }

        address owner = _strategyOwners[strategyId];
        AssetAllocation[] memory allocations = _strategyAllocations[strategyId];

        uint256 totalValue = _calculatePortfolioValue(owner, allocations);
        if (totalValue == 0) {
            return (false, "No portfolio value");
        }

        // 检查每个资产的偏离
        for (uint256 i = 0; i < allocations.length; i++) {
            uint256 currentValue = _getAssetValue(owner, allocations[i].token);
            uint256 currentWeight = (currentValue * TOTAL_WEIGHT) / totalValue;
            uint256 targetWeight = allocations[i].targetWeight;

            uint256 deviation = currentWeight > targetWeight
                ? currentWeight - targetWeight
                : targetWeight - currentWeight;

            if (deviation >= metadata.rebalanceThreshold) {
                return (true, "Threshold exceeded");
            }
        }

        return (false, "Within threshold");
    }

    /**
     * @notice 获取当前资产权重
     */
    function getCurrentWeights(
        bytes32 strategyId
    ) external view returns (uint256[] memory weights) {
        address owner = _strategyOwners[strategyId];
        AssetAllocation[] memory allocations = _strategyAllocations[strategyId];

        uint256 totalValue = _calculatePortfolioValue(owner, allocations);
        weights = new uint256[](allocations.length);

        if (totalValue > 0) {
            for (uint256 i = 0; i < allocations.length; i++) {
                uint256 assetValue = _getAssetValue(owner, allocations[i].token);
                weights[i] = (assetValue * TOTAL_WEIGHT) / totalValue;
            }
        }
    }

    /**
     * @notice 获取投资组合总价值
     */
    function getPortfolioValue(bytes32 strategyId) external view returns (uint256) {
        address owner = _strategyOwners[strategyId];
        AssetAllocation[] memory allocations = _strategyAllocations[strategyId];
        return _calculatePortfolioValue(owner, allocations);
    }

    /**
     * @notice 获取再平衡历史
     */
    function getRebalanceHistory(
        bytes32 strategyId
    ) external view returns (RebalanceRecord[] memory) {
        return _rebalanceHistory[strategyId];
    }

    // ============ 内部函数 ============

    /**
     * @notice 计算投资组合总价值
     */
    function _calculatePortfolioValue(
        address user,
        AssetAllocation[] memory allocations
    ) internal view returns (uint256 totalValue) {
        for (uint256 i = 0; i < allocations.length; i++) {
            totalValue += _getAssetValue(user, allocations[i].token);
        }
    }

    /**
     * @notice 获取用户持有某资产的价值
     */
    function _getAssetValue(
        address user,
        address token
    ) internal view returns (uint256) {
        uint256 balance = IERC20(token).balanceOf(user);
        if (balance == 0) return 0;

        uint256 price = priceOracle.getPrice(token);
        return (balance * price) / 1e18;
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
