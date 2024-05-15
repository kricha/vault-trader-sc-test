// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;
pragma abicoder v2;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IRouter} from "@aero/contracts/contracts/interfaces/IRouter.sol";
import {IPool} from "@aero/contracts/contracts/interfaces/IPool.sol";
import {IPoolFactory} from "@aero/contracts/contracts/interfaces/factories/IPoolFactory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "v4-core/libraries/FullMath.sol";

interface IERC20 is IERC20Metadata {}

interface IWETH9 is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

contract TraderAero is Ownable {
    IRouter private immutable ROUTER;
    address private _swapper;
    IWETH9 private immutable _weth;

    constructor(address aRouter, address WETH) Ownable(_msgSender()) {
        ROUTER = IRouter(aRouter);
        _weth = IWETH9(WETH);
        setSwapper(_msgSender());
    }

    function swapStableExactIn(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    ) public onlySwapper returns (uint256[] memory amounts) {
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

        require(
            IERC20(tokenIn).approve(address(ROUTER), amountIn + 1),
            "univ2 approve failed"
        );

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route({
            from: tokenIn,
            to: tokenOut,
            stable: false,
            factory: ROUTER.defaultFactory()
        });

        return
            ROUTER.swapExactTokensForTokens(
                amountIn,
                amountOut,
                routes,
                address(this),
                block.timestamp
            );
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

    function getStablePrice(
        address tokenA,
        address tokenB,
        bool stable
    ) public view returns (uint256) {
        (uint256 reserveA, uint256 reserveB) = ROUTER.getReserves(
            tokenA,
            tokenB,
            stable,
            ROUTER.defaultFactory()
        );

        uint256 adjResA = (reserveA * 1e18) / (10 ** IERC20(tokenA).decimals());
        uint8 tokenBDec = IERC20(tokenB).decimals();
        uint256 adjResB = (reserveB * 1e18) / (10 ** tokenBDec);

        return ((10 ** tokenBDec) * adjResB) / adjResA;
    }

    receive() external payable {}
}
