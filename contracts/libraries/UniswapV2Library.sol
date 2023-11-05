pragma solidity >=0.5.0;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import './SafeMath.sol';

library UniswapV2Library {
    using SafeMath for uint;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    // 对两个 token 进行排序
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'UniswapV2Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2Library: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    // 计算pair合约地址
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(
            uint(
                keccak256(
                    abi.encodePacked(
                        hex'ff',
                        factory,
                        keccak256(abi.encodePacked(token0, token1)),
                        hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f' 
                        // init code hash
                        // 该值其实是 UniswapV2Pair 合约的 creationCode 的哈希值
                        // 可以在 UniswapV2Factory 合约中添加以下常量获取到该值：
                        // bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(UniswapV2Pair).creationCode));
                        // INIT_CODE_PAIR_HASH 的值是带有 0x 开头的。
                        // 而以上硬编码的 init code hash 前面已经加了 hex 关键字，所以单引号里的哈希值就不再需要 0x 开头。
                    )
                )
            )
        );
    }

    // fetches and sorts the reserves for a pair
    // 获取两个 token 在池子里的储备量
    function getReserves(
        address factory,
        address tokenA,
        address tokenB
    ) internal view returns (uint reserveA, uint reserveB) {
        (address token0, ) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1, ) = IUniswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    // 根据给定的两个 token 的储备量和其中一个 token 数量，计算得到另一个 token 等值的数值
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'UniswapV2Library: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    // 根据给定的两个 token 的储备量和输入的 token 数量，计算得到输出的 token 数量，该计算会扣减掉 0.3% 的手续费
    // 根据 AMM 的原理，恒定乘积公式「x * y = K」，兑换前后 K 值不变。因此，在不考虑交易手续费的情况下，以下公式会成立：
    // reserveIn * reserveOut = (reserveIn + amountIn) * (reserveOut - amountOut)
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    // 根据给定的两个 token 的储备量和输出的 token 数量，计算得到输入的 token 数量，该计算会扣减掉 0.3% 的手续费
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }

    // performs chained getAmountOut calculations on any number of pairs
    // 根据兑换路径和输入数量，计算得到兑换路径中每个交易对的输出数量
    // path 表示交易资产的路由路径。这是一个地址数组，其中每个地址代表交易过程中将要经过的一个代币。
    // 在一个典型的代币兑换交易中，你可能想要将代币 A 兑换为代币 B，但是直接的交易对可能不存在或者流动性不足。
    // 在这种情况下，可以通过其他代币作为中间步骤来实现兑换，例如 A -> C -> B，这里 C 就是中介代币。
    // ---
    // 该函数会计算 path 中每一个中间资产和最终资产的数量，比如 path 为 [A,B,C]，
    // 则会先将 A 兑换成 B，再将 B 兑换成 C。返回值则是一个数组，
    // 第一个元素是 A 的数量，即 amountIn，而第二个元素则是兑换到的代币 B 的数量，最后一个元素则是最终要兑换得到的代币 C 的数量。
    // 从代码中还可看到，每一次兑换其实都调用了 getAmountOut 函数，
    // 这也意味着每一次中间兑换都会扣减千分之三的交易手续费。那如果兑换两次，实际支付假设为 1000，那最终实际兑换得到的价值只剩下：
    // 1000 * (1 - 0.003) * (1 - 0.003) = 994.009
    // 即实际支付的交易手续费将近千分之六了。兑换路径越长，实际扣减的交易手续费会更多，所以兑换路径一般不宜过长。
    function getAmountsOut(
        address factory,
        uint amountIn,
        address[] memory path
    ) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        // 第一个 token 的数量就是输入的 token 数量
        amounts[0] = amountIn;
        // 从第一个 token 开始，依次计算每个 token 的输出数量
        for (uint i; i < path.length - 1; i++) {
            // 获取当前 token 和下一个 token 的储备量
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);
            // 根据当前 token 的数量和储备量，计算得到下一个 token 的数量
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    // 根据兑换路径和输出数量，计算得到兑换路径中每个交易对的输入数量
    function getAmountsIn(
        address factory,
        uint amountOut,
        address[] memory path
    ) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
