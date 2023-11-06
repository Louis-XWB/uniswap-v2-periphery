pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol';

import '../libraries/UniswapV2Library.sol';
import '../interfaces/V1/IUniswapV1Factory.sol';
import '../interfaces/V1/IUniswapV1Exchange.sol';
import '../interfaces/IUniswapV2Router01.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/IWETH.sol';

// 闪电贷的例子，通过Uniswap V2进行闪电交换，然后用V1市场上的不同价格来换取利润
contract ExampleFlashSwap is IUniswapV2Callee {

    IUniswapV1Factory immutable factoryV1;
    address immutable factory;
    IWETH immutable WETH;

    constructor(address _factory, address _factoryV1, address router) public {
        factoryV1 = IUniswapV1Factory(_factoryV1);
        factory = _factory;
        WETH = IWETH(IUniswapV2Router01(router).WETH());
        // 将WETH地址设置为V2路由器的WETH地址
    }

    // needs to accept ETH from any V1 exchange and WETH. ideally this could be enforced, as in the router,
    // but it's not possible because it requires a call to the v1 factory, which takes too much gas
    receive() external payable {}

    // gets tokens/WETH via a V2 flash swap, swaps for the ETH/tokens on V1, repays V2, and keeps the rest!
    // uniswapV2Call函数是闪电互换的核心功能，会被Uniswap V2合约在交易完成时调用
    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external override {
        // 创建一个地址数组path，用来存储代币的交易路径
        address[] memory path = new address[](2);
        uint amountToken;
        uint amountETH;
        {
            // scope for token{0,1}, avoids stack too deep errors
            // 确保合约调用来自于V2 pair，且交易为单向的
            address token0 = IUniswapV2Pair(msg.sender).token0();
            address token1 = IUniswapV2Pair(msg.sender).token1();
            assert(msg.sender == UniswapV2Library.pairFor(factory, token0, token1)); // ensure that msg.sender is actually a V2 pair
            // 保证交易为单向的
            assert(amount0 == 0 || amount1 == 0); // this strategy is unidirectional

            // 设置交易路径，amount0为0时，交易路径为token1->token0，amount1为0时，交易路径为token0->token1
            path[0] = amount0 == 0 ? token0 : token1;
            path[1] = amount0 == 0 ? token1 : token0;
            // 设置交易金额
            amountToken = token0 == address(WETH) ? amount1 : amount0;
            amountETH = token0 == address(WETH) ? amount0 : amount1;
        }

        // 保证交易路径为WETH->token或token->WETH
        assert(path[0] == address(WETH) || path[1] == address(WETH)); // this strategy only works with a V2 WETH pair
        // 实例化IERC20接口的token变量，以便于调用代币合约
        IERC20 token = IERC20(path[0] == address(WETH) ? path[1] : path[0]);
        // 从V1工厂获取交换合约
        IUniswapV1Exchange exchangeV1 = IUniswapV1Exchange(factoryV1.getExchange(address(token))); // get V1 exchange

        // 如果amountToken大于0，执行从代币换成ETH的交换
        if (amountToken > 0) {
            // 从传入的data解码出滑点参数
            uint minETH = abi.decode(data, (uint)); // slippage parameter for V1, passed in by caller
            // 从V1交换合约中获取代币，然后将代币授权给V1交换合约
            token.approve(address(exchangeV1), amountToken);
            // 在V1上将代币换成ETH
            uint amountReceived = exchangeV1.tokenToEthSwapInput(amountToken, minETH, uint(-1));
            // 计算需要还给V2多少ETH
            uint amountRequired = UniswapV2Library.getAmountsIn(factory, amountToken, path)[0];
            // 保证我们从V1交换合约中获取的ETH大于我们需要还给V2的ETH
            assert(amountReceived > amountRequired); // fail if we didn't get enough ETH back to repay our flash loan
            // 将WETH存入V2 pair
            WETH.deposit{value: amountRequired}();
            // 将WETH还给V2 pair 合约
            assert(WETH.transfer(msg.sender, amountRequired)); // return WETH to V2 pair
            
            // 将剩余的ETH发送给sender
            (bool success, ) = sender.call{value: amountReceived - amountRequired}(new bytes(0)); // keep the rest! (ETH)
            assert(success);
        } else {
            // 如果amountToken没有大于0，执行从ETH换成代币的交换
            // 从传入的data解码出滑点参数
            // 从闪电互换调用中解码出最小代币数量
            uint minTokens = abi.decode(data, (uint)); // slippage parameter for V1, passed in by caller
            // 从WETH合约中取出ETH
            WETH.withdraw(amountETH);
            // 在V1上将ETH换成代币
            uint amountReceived = exchangeV1.ethToTokenSwapInput{value: amountETH}(minTokens, uint(-1));
            // 计算需要还给V2多少代币
            uint amountRequired = UniswapV2Library.getAmountsIn(factory, amountETH, path)[0];
            // 保证我们从V1交换合约中获取的代币大于我们需要还给V2的代币
            assert(amountReceived > amountRequired); // fail if we didn't get enough tokens back to repay our flash loan
            // 将代币还给V2 pair合约
            assert(token.transfer(msg.sender, amountRequired)); // return tokens to V2 pair
            // 将剩余的代币发送给sender
            assert(token.transfer(sender, amountReceived - amountRequired)); // keep the rest! (tokens)
        }
    }
}
