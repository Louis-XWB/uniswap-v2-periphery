pragma solidity =0.6.6;

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/lib/contracts/libraries/TransferHelper.sol';

import './interfaces/IUniswapV2Router02.sol';
import './libraries/UniswapV2Library.sol';
import './libraries/SafeMath.sol';
import './interfaces/IERC20.sol';
import './interfaces/IWETH.sol';

contract UniswapV2Router02 is IUniswapV2Router02 {
    using SafeMath for uint;

    address public immutable override factory;
    address public immutable override WETH;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'UniswapV2Router: EXPIRED');
        _;
    }

    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    // 添加流动性，将两种代币添加到流动性池中，同时获得流动性代币 LP-Token。
    // amountADesired 和 amountBDesired 是预期支付的两个代币的数量
    // amountAMin 和 amountBMin 则是用户可接受的最小成交数量，一般是由前端根据预期值和滑点值计算得出的。
    // 用户能够接受的添加到流动性池的代币A和代币B的最小数量。这是为了防止交易在价格滑点过大时执行。
    // 比如，预期值 amountADesired 为 1000，设置的滑点为 0.5%，那就可以计算得出可接受的最小值 amountAMin 为 1000 * (1 - 0.5%) = 995。
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        }
        // 获取 tokenA 和 tokenB 的储备量
        (uint reserveA, uint reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);

        // 如果储备量为 0，说明是第一次添加流动性，直接按照预期值添加即可
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            // 如果计算得出的结果值 amountBOptimal 不比 amountBDesired 大，且不会小于 amountBMin，
            // 就可将 amountADesired 和该 amountBOptimal 作为结果值返回。
            uint amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                // 如果 amountBOptimal 大于 amountBDesired，则根据 amountBDesired 计算得出需要支付多少 tokenA
                // 得到 amountAOptimal，只要 amountAOptimal 不大于 amountADesired 且不会小于 amountAMin，
                // 就可将 amountAOptimal 和 amountBDesired 作为结果值返回。
                uint amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    // 添加流动性，将两种代币添加到流动性池中，同时获得流动性代币 LP-Token。
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,// tokenADesired 和 tokenBDesired 是预期支付的两个代币的数量
        uint amountBDesired,
        uint amountAMin, // amountAMin 和 amountBMin 则是用户可接受的最小成交数量，一般是由前端根据预期值和滑点值计算得出的。比如，预期值 amountADesired 为 1000
        uint amountBMin, // 设置的滑点为 0.5%，那就可以计算得出可接受的最小值 amountAMin 为 1000 * (1 - 0.5%) = 995。
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IUniswapV2Pair(pair).mint(to);
    }

    // 添加流动性，其中一个 token 是 ETH
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable virtual override ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value, // 预期支付的 ETH 金额也是直接从 msg.value 读取的
            amountTokenMin,
            amountETHMin
        );
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IUniswapV2Pair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    // 移除流动性，会换回两种 ERC20 代币，同时销毁流动性代币 LP-Token。
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        // 先计算出 pair 合约地址
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);

        // 将流动性代币从用户划转到 pair 合约地址
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair

        // 接着销毁流动性代币，将两种代币从流动性池中取回
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(to);

        // 确定哪个代币是 tokenA，哪个代币是 tokenB
        (address token0, ) = UniswapV2Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);

        // 最后判断取回的代币数量是否满足用户的最小值要求
        require(amountA >= amountAMin, 'UniswapV2Router: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'UniswapV2Router: INSUFFICIENT_B_AMOUNT');
    }

    // 移除流动性，其中一个 token 是 ETH
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        // 调用 WETH 的 withdraw 函数将 WETH 转为 ETH，再将 ETH 转给用户
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    // 移除流动性，用户会提供签名数据使用 permit 方式完成授权操作，这样就不需要用户在钱包中进行授权操作了。
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint amountA, uint amountB) {
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint amountToken, uint amountETH) {
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    // 和 removeLiquidityETH 一样，不同的地方在于支持转账时支付费用
    // 有一些项目 token，其合约实现上，在进行 transfer 的时候，就会扣减掉部分金额作为费用，或作为税费缴纳，或锁仓处理，或替代 ETH 来支付 GAS 费。
    // 总而言之，就是某些 token 在进行转账时是会产生损耗的，实际到账的数额不一定就是传入的数额。该函数主要支持的就是这类 token。
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity(token, WETH, liquidity, amountTokenMin, amountETHMin, address(this), deadline);
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    // 支持使用链下签名的方式进行授权
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint amountETH) {
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        uint value = approveMax ? uint(-1) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token,
            liquidity,
            amountTokenMin,
            amountETHMin,
            to,
            deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    // 遍历整个兑换路径，并对路径中每两个配对的 token 调用 pair 合约的兑换函数，实现底层的兑换处理
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        // 遍历整个兑换路径
        for (uint i; i < path.length - 1; i++) {
            // 获取当前 token 和下一个 token 的地址
            (address input, address output) = (path[i], path[i + 1]);

            // 排序获得 token0 和 token1
            (address token0, ) = UniswapV2Library.sortTokens(input, output);

            // 获取当前 token 和下一个 token 的储备量
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));

            // 获取当前 token 和下一个 token 的 pair 合约地址
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;

            // 调用 pair 合约的兑换函数，将当前 token 兑换成下一个 token
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output)).swap(
                amount0Out,
                amount1Out,
                to,
                new bytes(0)
            );
        }
    }
    // 交易 tokenA -> tokenB，支付的数量是指定的，而兑换回的数量则是未确定的
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        // 根据指定的输入数量和交易路径，计算得到输出的数量
        // path，是由前端 SDK 计算出最优路径后传给合约的
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);

        // 确保输出的数量不小于用户指定的最小值
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');

        // 将 tokenA 从用户地址划转到 pair 合约地址
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            UniswapV2Library.pairFor(factory, path[0], path[1]),
            amounts[0]
        );

        // 接着调用 _swap 函数，将 tokenA 兑换成 tokenB
        _swap(amounts, path, to);
    }

    // 交易 tokenA -> tokenB，兑换回的数量是未确定的
    // 指定想要换回的 tokenB 的数量，而需要支付的 tokenA 的数量则是越少越好
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {

        // 根据指定的输出数量和交易路径，计算得到输入的数量
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);

        // 确保输入的数量不大于用户指定的最大值
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');

        // 将 tokenA 从用户地址划转到 pair 合约地址
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            UniswapV2Library.pairFor(factory, path[0], path[1]),
            amounts[0]
        );

        // 接着调用 _swap 函数，将 tokenA 兑换成 tokenB
        _swap(amounts, path, to);
    }

    // 指定 ETH 数量兑换 ERC20
    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable virtual override ensure(deadline) returns (uint[] memory amounts) {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    // 用 ERC20 兑换成指定数量的 ETH
    function swapTokensForExactETH(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            UniswapV2Library.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    // 用指定数量的 ERC20 兑换 ETH
    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            UniswapV2Library.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    // 用 ETH 兑换指定数量的 ERC20
    function swapETHForExactTokens(
        uint amountOut,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable virtual override ensure(deadline) returns (uint[] memory amounts) {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'UniswapV2Router: EXCESSIVE_INPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    // 指定数量的 ERC20 兑换 ERC20，支持转账时扣费
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            // 获取当前 token 和下一个 token 的地址
            (address input, address output) = (path[i], path[i + 1]);

            // 排序获得 token0 和 token1
            (address token0, ) = UniswapV2Library.sortTokens(input, output);

            // 获取当前 token 和下一个 token 的 pair 合约地址
            IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output));

            uint amountInput;
            uint amountOutput;
            {
                // scope to avoid stack too deep errors
                // 获取当前 token 和下一个 token 的储备量
                (uint reserve0, uint reserve1, ) = pair.getReserves();

                // 确定哪个代币是 token0，哪个代币是 token1
                (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);

                // 因为 input 代币转账时可能会有损耗，所以在 pair 合约里实际收到多少代币，只能通过查出 pair 合约当前的余额，
                // 再减去该代币已保存的储备量，这才能计算出来实际值。
                amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);

                // 根据 amountInput 和储备量计算得出 amountOutput
                amountOutput = UniswapV2Library.getAmountOut(amountInput, reserveInput, reserveOutput);
            }

            // 获取当前 token 和下一个 token 的实际输出数量
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            
            // 获取当前 token 和下一个 token 的接收地址
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;

            // 调用 pair 合约的兑换函数，将当前 token 兑换成下一个 token
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    // 指定数量的 ETH 兑换 ERC20，支持转账时扣费
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        // 将 amountIn 转账给到 pair 合约地址
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            UniswapV2Library.pairFor(factory, path[0], path[1]),
            amountIn
        );

        // 读取出接收地址在兑换路径中最后一个代币的余额
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);

        // 调用内部函数实现路径中每一步的兑换
        _swapSupportingFeeOnTransferTokens(path, to);

        // 再验证接收者最终兑换得到的资产数量不能小于指定的最小值
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );

        //因为此类代币转账时可能会有损耗，所以就无法使用恒定乘积公式计算出最终兑换的资产数量，因此用交易后的余额减去交易前的余额来计算得出实际值。
    }

    // 指定数量的 ERC20 兑换 ETH，支持转账时扣费
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable virtual override ensure(deadline) {
        require(path[0] == WETH, 'UniswapV2Router: INVALID_PATH');
        uint amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn));
        uint balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        require(path[path.length - 1] == WETH, 'UniswapV2Router: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            UniswapV2Library.pairFor(factory, path[0], path[1]),
            amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    // 直接调用 UniswapV2Library 的函数，计算出兑换的数量
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    // 直接调用 UniswapV2Library 的函数，计算出兑换的数量，该计算会扣减掉 0.3% 的手续费
    function getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) public pure virtual override returns (uint amountOut) {
        return UniswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    // 直接调用 UniswapV2Library 的函数，计算出要输入的数量，该计算会扣减掉 0.3% 的手续费
    function getAmountIn(
        uint amountOut,
        uint reserveIn,
        uint reserveOut
    ) public pure virtual override returns (uint amountIn) {
        return UniswapV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(
        uint amountIn,
        address[] memory path
    ) public view virtual override returns (uint[] memory amounts) {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(
        uint amountOut,
        address[] memory path
    ) public view virtual override returns (uint[] memory amounts) {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }
}
