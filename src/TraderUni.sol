// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
pragma abicoder v2;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "v4-core/libraries/FullMath.sol";

interface IERC20 is IERC20Metadata {}

interface IWETH9 is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

// import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol"; // not working on sepolia testnet
// need to recreate own interface with struct because sepolia router doesn't have deadline option
interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut);
}

contract TraderUni is Ownable {
    event Trade(
        address indexed addrIn,
        address indexed addrOut,
        uint amountIn,
        uint amountOut
    );
    address private immutable _v2Factory;
    IUniswapV2Router02 private immutable _v2Router;
    address private immutable _v3Factory;
    ISwapRouter private immutable _v3Router;
    IWETH9 private immutable _weth;
    address private _swapper;

    constructor(
        address v2Factory,
        address v2Router,
        address v3Factory,
        address v3Router,
        address WETH
    ) Ownable(_msgSender()) {
        _v2Factory = v2Factory;
        _v2Router = IUniswapV2Router02(v2Router);
        _v3Factory = v3Factory;
        _v3Router = ISwapRouter(v3Router);
        _weth = IWETH9(WETH);
        setSwapper(_msgSender());
    }

    function swapV2ExactIn(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) public onlySwapper returns (bool) {
        if (_isEthWeth(tokenIn)) {
            tokenIn = address(_weth);
            uint256 _currentWethBal = IERC20(tokenIn).balanceOf(address(this));
            if (_currentWethBal < amountIn) {
                _wrapEth(amountIn - _currentWethBal + 1);
            }
        }

        if (_isEthWeth(tokenOut)) {
            tokenOut = address(_weth);
        }

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        require(
            IERC20(tokenIn).approve(address(_v2Router), amountIn + 1),
            "univ2 approve failed"
        );

        uint[] memory amounts = _v2Router.swapExactTokensForTokens(
            amountIn,
            amountOut,
            path,
            address(this),
            block.timestamp
        );
        emit Trade(tokenIn, tokenOut, amounts[0], amounts[1]);
        return true;
    }

    function swapV3ExactIn(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) public onlySwapper returns (bool) {
        if (_isEthWeth(tokenIn)) {
            tokenIn = address(_weth);
            uint256 _currentWethBal = IERC20(tokenIn).balanceOf(address(this));
            if (_currentWethBal < amountIn) {
                _wrapEth(amountIn - _currentWethBal + 1);
            }
        }

        if (_isEthWeth(tokenOut)) {
            tokenOut = address(_weth);
        }

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: 500,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: amountOut,
                sqrtPriceLimitX96: 0
            });

        require(
            IERC20(tokenIn).approve(address(_v3Router), amountIn + 1),
            "univ3 approve failed"
        );

        uint256 retAmountOut = _v3Router.exactInputSingle(params);
        emit Trade(tokenIn, tokenOut, amountIn, retAmountOut);
        return true;
    }

    function setSwapper(address adr) public onlyOwner {
        _swapper = adr;
    }

    modifier onlySwapper() {
        require(_swapper == _msgSender(), "not authorized trader");
        _;
    }

    function withdrawTokensWithUnwrapIfNecessary(
        address token
    ) public onlyOwner {
        address _scAddr = address(this);
        if (_isEthWeth(token)) {
            token = address(_weth);
            _unwrapEth(IERC20(token).balanceOf(_scAddr));
            (bool sent, ) = owner().call{value: _scAddr.balance}("");
            require(sent, "Failed to send Ether");
        } else {
            IERC20(token).transfer(owner(), IERC20(token).balanceOf(_scAddr));
        }
    }

    function _isEthWeth(address token) private view returns (bool) {
        return token == address(0) || token == address(_weth);
    }

    function _wrapEth(uint256 value) internal {
        _weth.deposit{value: value}();
    }

    function _unwrapEth(uint256 value) internal {
        _weth.withdraw(value);
    }

    receive() external payable {}

    //FROM lib/v2-periphery/contracts/libraries/UniswapV2Library.sol because of compiler incomp
    function _sortTokens(
        address tokenA,
        address tokenB
    ) private pure returns (address token0, address token1) {
        require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }

    function getV2PairPrice(
        address tokenA,
        address tokenB
    ) public view returns (uint256) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);

        address pair = IUniswapV2Factory(_v2Factory).getPair(token0, token1);
        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pair)
            .getReserves();
        (uint256 reserveA, uint256 reserveB) = tokenA == token0
            ? (reserve0, reserve1)
            : (reserve1, reserve0);

        return (reserveB * 1e18) / reserveA;
    }

    function getV3PairPrice(
        address tokenA,
        address tokenB
    ) public view returns (uint256) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        address pool = IUniswapV3Factory(_v3Factory).getPool(
            token0,
            token1,
            500
        );
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
        uint256 price = FullMath.mulDiv(
            uint256(sqrtPriceX96) ** 2,
            10 ** IERC20(token0).decimals(),
            1 << 192
        );

        return tokenA == token0 ? price : 1e36 / price;
    }
}
