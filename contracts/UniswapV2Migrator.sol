pragma solidity =0.6.6;

import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import './interfaces/IUniswapV2Migrator.sol';
import './interfaces/V1/IUniswapV1Factory.sol';
import './interfaces/V1/IUniswapV1Exchange.sol';
import './interfaces/IUniswapV2Router01.sol';
import './interfaces/IERC20.sol';

// 负责将合约从V1迁移到V2
// 帮助用户将流动性从 V1 升级到 V2
// 流动性迁移: 用户可以一键迁移其在 V1 池中的流动性代币到 V2，而不需要手动移除 V1 的流动性再将其添加到 V2。
// LP 代币转换: 迁移过程中，用户的 V1 流动性提供者(LP) 代币会被转换成 V2 的 LP 代币。
// 状态和储备金复制: 迁移合约能够复制现有的流动性池状态，包括储备金的数量，确保在 V1 和 V2 之间平滑过渡。
// 最小化停机时间: 流动性迁移是自动化的，这最小化了流动性提供者因迁移而面临的交易不可用时间。
contract UniswapV2Migrator is IUniswapV2Migrator {
    // V1工厂合约地址
    IUniswapV1Factory immutable factoryV1;
    // V2路由合约地址
    IUniswapV2Router01 immutable router;

    constructor(address _factoryV1, address _router) public {
        factoryV1 = IUniswapV1Factory(_factoryV1);
        router = IUniswapV2Router01(_router);
    }

    // needs to accept ETH from any v1 exchange and the router. ideally this could be enforced, as in the router,
    // but it's not possible because it requires a call to the v1 factory, which takes too much gas
    // 允许接收ETH
    receive() external payable {}


    function migrate(
        address token,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external override {
        // 获取V1交易合约地址， V1是token/ETH交易对 因此输入token即可查询对应地址
        IUniswapV1Exchange exchangeV1 = IUniswapV1Exchange(factoryV1.getExchange(token));
        // 获取V1交易合约地址的流动性代币余额
        uint liquidityV1 = exchangeV1.balanceOf(msg.sender);
        // 将流动性代币从用户地址转移到当前合约地址
        require(exchangeV1.transferFrom(msg.sender, address(this), liquidityV1), 'TRANSFER_FROM_FAILED');
        // 移除V1流动性，返回token/ETH到本合约中
        (uint amountETHV1, uint amountTokenV1) = exchangeV1.removeLiquidity(liquidityV1, 1, 1, uint(-1));
        // 授权给router合约进行路径查找后的token转账
        TransferHelper.safeApprove(token, address(router), amountTokenV1);
        // router 添加流动性到 V2 ，并返回新的代币和 ETH 数量
        (uint amountTokenV2, uint amountETHV2, ) = router.addLiquidityETH{value: amountETHV1}(
            token,
            amountTokenV1,
            amountTokenMin,
            amountETHMin,
            to,
            deadline
        );

        // 将多余的token和ETH退还给用户
        if (amountTokenV1 > amountTokenV2) {
            // 重置授权额度为 0
            TransferHelper.safeApprove(token, address(router), 0); // be a good blockchain citizen, reset allowance to 0
            TransferHelper.safeTransfer(token, msg.sender, amountTokenV1 - amountTokenV2);
        } else if (amountETHV1 > amountETHV2) {
            // addLiquidityETH guarantees that all of amountETHV1 or amountTokenV1 will be used, hence this else is safe
            TransferHelper.safeTransferETH(msg.sender, amountETHV1 - amountETHV2);
        }
    }
}
