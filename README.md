## Uniswap 系列汇总

[uniswap-v1](https://github.com/Louis-XWB/Uniswap-v1/)

[uniswap-v2-core](https://github.com/Louis-XWB/uniswap-v2-core)

[uniswap-v2-periphery](https://github.com/Louis-XWB/uniswap-v2-periphery)

[uniswap-v3-core](https://github.com/Louis-XWB/uniswap-v3-core)

[uniswap-v3-periphery](https://github.com/Louis-XWB/uniswap-v3-periphery)


# uniswap-v2-periphery 源码学习

## Intro

Uniswap V2 Periphery 是 Uniswap V2 协议中与 core 合约配套使用的一系列智能合约。这些外围合约提供了额外的功能和接口，使得与核心合约的互动更加便捷、安全和高效。以下是 Uniswap V2 Periphery 提供的一些关键功能和组件：

1) **Router**: Router 合约是 Uniswap V2 中最常用的外围合约。它提供了交易代币、添加和移除流动性等功能的便利方法。Router 合约处理多步骤的交易，如从代币 A 转换到代币 B，而这可能需要先将 A 转换到 ETH，然后再从 ETH 转换到 B。
2) **Flash Swaps**: Uniswap V2 引入了闪电交换（Flash Swaps），允许用户在支付代币之前先借用它们，这可以用于套利、抵押贷款偿还等复杂操作。
3) **Migration**: 为了帮助用户从 Uniswap V1 迁移到 V2，提供了一个迁移合约，它能够帮助用户将流动性从 V1 迁移到 V2。
4) **Library**: Library 合约，如 UniswapV2Library，提供了一组用于与 Uniswap V2 对接的实用工具函数，例如获取储备金、计算出价和获取最优路由等。

## Code Learning

* [UniswapV2Migrator.sol](https://github.com/Louis-XWB/uniswap-v2-periphery/blob/master/contracts/UniswapV2Migrator.sol) - 负责将合约从V1迁移到V2

* [UniswapV2Library.sol](https://github.com/Louis-XWB/uniswap-v2-periphery/blob/master/contracts/libraries/UniswapV2Library.sol) - 提供了一系列用于与Uniswap V2合约交互的辅助函数

* [UniswapV2Router02.sol](https://github.com/Louis-XWB/uniswap-v2-periphery/blob/master/contracts/UniswapV2Router02.sol) - 路由器的第二版实现，扩展了第一版（UniswapV2Router01）的功能。提供了与 V2 协议交互的接口，支持代币交换、添加流动性、移除流动性等操作。

* [ExampleFlashSwap.sol](https://github.com/Louis-XWB/uniswap-v2-periphery/blob/master/contracts/examples/ExampleFlashSwap.sol) - 举例如何执行一个flash swap（闪电贷）操作。闪电贷允许用户借用任何数量的ERC-20代币，只要在交易结束时返还同等价值的代币即可。  




## FAQ

1) 闪电互换的运作流程

    闪电互换是DeFi中一种特殊类型的交易，允许用户借用任何数量的ERC-20代币，只要在交易结束时返还同等价值的代币即可。

    闪电互换的运作流程如下：
    
    * **触发交易**： 用户或者智能合约开始一个闪电swap，通常是为了利用两个市场之间的价格差异进行套利、执行去中心化贷款或其他复杂的金融策略。
    * **借入资产**： 用户从Uniswap的流动性池中借入代币（例如，如果他们预计该代币的价格会下降，或者他们可以在另一个市场上卖出更高价）。
    * **执行策略**： 用户可以使用这些代币进行交易、套利或其他操作，而无需提供初始的资金。
    * **还款和费用**： 在同一次交易中，用户必须返还等价值的借入代币加上一定的费用。通常，如果用户未能在单笔交易中返还资金，整个交易会被**回滚**。
    

## Resources

Uniswap-v2 doc: [v2/overview](https://docs.uniswap.org/contracts/v2/overview)

Uniswap-v2 Whitepaper: [uniswap.org/whitepaper.pdf](https://docs.uniswap.org/whitepaper.pdf)
