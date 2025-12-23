// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {ShieldCore} from "../src/core/ShieldCore.sol";
import {DCAExecutor} from "../src/strategies/DCAExecutor.sol";
import {RebalanceExecutor} from "../src/strategies/RebalanceExecutor.sol";
import {StopLossExecutor} from "../src/strategies/StopLossExecutor.sol";
import {SubscriptionManager} from "../src/subscriptions/SubscriptionManager.sol";
import {SpendingLimitEnforcer} from "../src/caveats/SpendingLimitEnforcer.sol";
import {AllowedTargetsEnforcer} from "../src/caveats/AllowedTargetsEnforcer.sol";
import {TimeBoundEnforcer} from "../src/caveats/TimeBoundEnforcer.sol";

/**
 * @title DeployShieldProtocol
 * @notice 部署 Shield Protocol 所有合约
 *
 * 使用方法:
 * 1. 设置环境变量:
 *    - PRIVATE_KEY: 部署者私钥
 *    - RPC_URL: RPC 节点地址
 *    - UNISWAP_ROUTER: Uniswap V3 Router 地址
 *    - WETH: WETH 地址
 *
 * 2. 运行部署:
 *    forge script script/Deploy.s.sol:DeployShieldProtocol --rpc-url $RPC_URL --broadcast
 */
contract DeployShieldProtocol is Script {
    // Sepolia 测试网地址
    address constant UNISWAP_V3_ROUTER_SEPOLIA = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant WETH_SEPOLIA = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address constant USDC_SEPOLIA = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    // 部署的合约地址
    ShieldCore public shieldCore;
    DCAExecutor public dcaExecutor;
    RebalanceExecutor public rebalanceExecutor;
    StopLossExecutor public stopLossExecutor;
    SubscriptionManager public subscriptionManager;
    SpendingLimitEnforcer public spendingLimitEnforcer;
    AllowedTargetsEnforcer public allowedTargetsEnforcer;
    TimeBoundEnforcer public timeBoundEnforcer;
    MockPriceOracle public priceOracle;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying Shield Protocol...");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 1. 部署核心合约
        shieldCore = new ShieldCore();
        console.log("ShieldCore deployed at:", address(shieldCore));

        address uniswapRouter = vm.envOr("UNISWAP_ROUTER", UNISWAP_V3_ROUTER_SEPOLIA);
        address weth = vm.envOr("WETH", WETH_SEPOLIA);

        // 2. 部署价格预言机 (测试网用 Mock)
        priceOracle = new MockPriceOracle();
        console.log("MockPriceOracle deployed at:", address(priceOracle));

        // 设置初始价格
        priceOracle.setPrice(weth, 2500e18);  // ETH = $2500
        priceOracle.setPrice(USDC_SEPOLIA, 1e18);  // USDC = $1

        // 3. 部署策略执行器
        dcaExecutor = new DCAExecutor(
            address(shieldCore),
            uniswapRouter,
            weth
        );
        console.log("DCAExecutor deployed at:", address(dcaExecutor));

        rebalanceExecutor = new RebalanceExecutor(
            address(shieldCore),
            uniswapRouter,
            address(priceOracle),
            USDC_SEPOLIA
        );
        console.log("RebalanceExecutor deployed at:", address(rebalanceExecutor));

        stopLossExecutor = new StopLossExecutor(
            address(shieldCore),
            uniswapRouter,
            address(priceOracle)
        );
        console.log("StopLossExecutor deployed at:", address(stopLossExecutor));

        // 4. 部署订阅管理器
        subscriptionManager = new SubscriptionManager(address(shieldCore));
        console.log("SubscriptionManager deployed at:", address(subscriptionManager));

        // 5. 部署 Caveat 执行器
        spendingLimitEnforcer = new SpendingLimitEnforcer();
        console.log("SpendingLimitEnforcer deployed at:", address(spendingLimitEnforcer));

        allowedTargetsEnforcer = new AllowedTargetsEnforcer();
        console.log("AllowedTargetsEnforcer deployed at:", address(allowedTargetsEnforcer));

        timeBoundEnforcer = new TimeBoundEnforcer();
        console.log("TimeBoundEnforcer deployed at:", address(timeBoundEnforcer));

        // 6. 配置授权
        shieldCore.addAuthorizedExecutor(address(dcaExecutor));
        shieldCore.addAuthorizedExecutor(address(rebalanceExecutor));
        shieldCore.addAuthorizedExecutor(address(stopLossExecutor));
        shieldCore.addAuthorizedExecutor(address(subscriptionManager));
        console.log("Authorized executors configured");

        vm.stopBroadcast();

        // 输出部署结果
        console.log("\n========== Deployment Summary ==========");
        console.log("Network: Sepolia");
        console.log("ShieldCore:", address(shieldCore));
        console.log("MockPriceOracle:", address(priceOracle));
        console.log("DCAExecutor:", address(dcaExecutor));
        console.log("RebalanceExecutor:", address(rebalanceExecutor));
        console.log("StopLossExecutor:", address(stopLossExecutor));
        console.log("SubscriptionManager:", address(subscriptionManager));
        console.log("SpendingLimitEnforcer:", address(spendingLimitEnforcer));
        console.log("AllowedTargetsEnforcer:", address(allowedTargetsEnforcer));
        console.log("TimeBoundEnforcer:", address(timeBoundEnforcer));
        console.log("=========================================\n");
    }
}

/**
 * @title DeployTestTokens
 * @notice 部署测试代币 (仅用于测试网)
 */
contract DeployTestTokens is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // 部署 Mock USDC
        MockERC20 mockUSDC = new MockERC20("Mock USDC", "USDC", 6);
        console.log("Mock USDC deployed at:", address(mockUSDC));

        // 部署 Mock WETH
        MockERC20 mockWETH = new MockERC20("Mock WETH", "WETH", 18);
        console.log("Mock WETH deployed at:", address(mockWETH));

        vm.stopBroadcast();
    }
}

/**
 * @title MockERC20
 * @notice 用于测试的 ERC20 代币
 */
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

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

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/**
 * @title MockPriceOracle
 * @notice 用于测试的价格预言机
 */
contract MockPriceOracle {
    mapping(address => uint256) public prices;

    function setPrice(address token, uint256 price) external {
        prices[token] = price;
    }

    function getPrice(address token) external view returns (uint256) {
        return prices[token];
    }
}
