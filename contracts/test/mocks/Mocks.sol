// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockERC20
 * @notice 用于测试的 ERC20 代币
 */
contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public override totalSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/**
 * @title MockSwapRouter
 * @notice 模拟 Uniswap V3 SwapRouter
 */
contract MockSwapRouter {
    // 模拟兑换比例 (1 USDC = 0.0004 ETH, 即 1 ETH = 2500 USDC)
    uint256 public exchangeRate = 4e14; // 0.0004 * 1e18

    // 针对特定代币对的汇率
    mapping(address => mapping(address => uint256)) public pairExchangeRate;

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

    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address recipient
    );

    function setExchangeRate(uint256 _rate) external {
        exchangeRate = _rate;
    }

    /// @notice 设置特定代币对的汇率
    function setExchangeRate(address tokenIn, address tokenOut, uint256 _rate) external {
        pairExchangeRate[tokenIn][tokenOut] = _rate;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external returns (uint256 amountOut) {
        // 从调用者转入 tokenIn
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        // 计算输出金额 - 优先使用特定代币对汇率
        uint256 rate = pairExchangeRate[params.tokenIn][params.tokenOut];
        if (rate == 0) {
            rate = exchangeRate;
        }

        // 如果 tokenIn 是 USDC (6 decimals), tokenOut 是 WETH (18 decimals)
        // amountOut = amountIn * exchangeRate / 1e6
        amountOut = (params.amountIn * rate) / 1e6;

        require(amountOut >= params.amountOutMinimum, "Slippage exceeded");
        require(block.timestamp <= params.deadline, "Deadline exceeded");

        // 铸造 tokenOut 给接收者 (测试用)
        MockERC20(params.tokenOut).mint(params.recipient, amountOut);

        emit SwapExecuted(params.tokenIn, params.tokenOut, params.amountIn, amountOut, params.recipient);
    }
}

/**
 * @title MockWETH
 * @notice 模拟 WETH
 */
contract MockWETH is MockERC20 {
    constructor() MockERC20("Wrapped Ether", "WETH", 18) {}

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        payable(msg.sender).transfer(amount);
        emit Transfer(msg.sender, address(0), amount);
    }

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }
}

/**
 * @title MockPriceOracle
 * @notice 模拟价格预言机
 */
contract MockPriceOracle {
    /// @notice 代币价格 (18 decimals, 以 USD 计价)
    mapping(address => uint256) public prices;

    event PriceUpdated(address indexed token, uint256 oldPrice, uint256 newPrice);

    /**
     * @notice 设置代币价格
     * @param token 代币地址
     * @param price 价格 (18 decimals)
     */
    function setPrice(address token, uint256 price) external {
        uint256 oldPrice = prices[token];
        prices[token] = price;
        emit PriceUpdated(token, oldPrice, price);
    }

    /**
     * @notice 批量设置价格
     * @param tokens 代币地址数组
     * @param _prices 价格数组
     */
    function setPrices(address[] calldata tokens, uint256[] calldata _prices) external {
        require(tokens.length == _prices.length, "Length mismatch");
        for (uint256 i = 0; i < tokens.length; i++) {
            prices[tokens[i]] = _prices[i];
        }
    }

    /**
     * @notice 获取代币价格
     * @param token 代币地址
     * @return price 价格 (18 decimals)
     */
    function getPrice(address token) external view returns (uint256 price) {
        price = prices[token];
        require(price > 0, "Price not set");
    }

    /**
     * @notice 模拟价格下跌
     * @param token 代币地址
     * @param dropPercentage 下跌百分比 (基点, 1000 = 10%)
     */
    function simulatePriceDrop(address token, uint256 dropPercentage) external {
        uint256 currentPrice = prices[token];
        require(currentPrice > 0, "Price not set");
        uint256 newPrice = (currentPrice * (10000 - dropPercentage)) / 10000;
        prices[token] = newPrice;
        emit PriceUpdated(token, currentPrice, newPrice);
    }

    /**
     * @notice 模拟价格上涨
     * @param token 代币地址
     * @param risePercentage 上涨百分比 (基点, 1000 = 10%)
     */
    function simulatePriceRise(address token, uint256 risePercentage) external {
        uint256 currentPrice = prices[token];
        require(currentPrice > 0, "Price not set");
        uint256 newPrice = (currentPrice * (10000 + risePercentage)) / 10000;
        prices[token] = newPrice;
        emit PriceUpdated(token, currentPrice, newPrice);
    }
}
