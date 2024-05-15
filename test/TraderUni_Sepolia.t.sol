// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {TraderUni, IWETH9} from "../src/TraderUni.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TraderHarness is
    TraderUni(
        0xc9f18c25Cfca2975d6eD18Fc63962EBd1083e978,
        0x86dcd3293C53Cf8EFd7303B57beb2a3F671dDE98,
        0x0227628f3F023bb0B980b67D528571c95c6DaC1c,
        0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E,
        0xD8200CEb9B832a4DB6Ed73f3b8B02f78F052cA7e
    )
{
    function exposed_wrapETH(uint256 value) external {
        return _wrapEth(value);
    }

    function exposed_unwrapETH(uint256 value) external {
        return _unwrapEth(value);
    }
}

contract TraderUniSepoliaTest is Test {
    using SafeERC20 for IERC20;

    TraderHarness public tsm;
    address tsmAddr;

    address constant WETH = 0xD8200CEb9B832a4DB6Ed73f3b8B02f78F052cA7e;
    address constant USDT = 0xdf0EE2E04F00ed0f608bEe9a1685664EaA5c898d;
    address constant USDC = 0x3571304CEFddA5915C2430E4e5A2cF95cC83f01C;

    IWETH9 WETH9 = IWETH9(WETH);

    address owner = vm.addr(0x1);
    address trader = vm.addr(0x2);

    uint256 userInitBalance = 10000000e6;
    uint256[] values;
    address[] recipients;
    uint256 totalValue = 0;

    function setUp() public {
        uint256 fork = vm.createFork("https://rpc.sepolia.org");
        vm.selectFork(fork);

        vm.startPrank(owner);
        tsm = new TraderHarness();
        tsmAddr = address(tsm);
        tsm.setSwapper(trader);
        vm.stopPrank();

        vm.label(USDT, "USDT");
        vm.label(WETH, "WETH");
        vm.label(0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E, "V3Router");

        console.log("Transfering ETH to Trader contract");
        vm.deal(tsmAddr, 10 ether);
    }

    function test_SetUp() public {
        assertEq(tsmAddr.balance, 10 ether);
    }

    function test_onlyOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                trader
            )
        );
        vm.prank(trader);
        tsm.withdrawTokensWithUnwrapIfNecessary(WETH);

        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                trader
            )
        );
        vm.prank(trader);
        tsm.setSwapper(address(0x0));
    }

    function test_onlySwapper() public {
        vm.expectRevert("not authorized trader");
        tsm.swapV3ExactIn(WETH, USDT, 1, 1);
    }

    function test_wrap_unwrapETH() public {
        tsm.exposed_wrapETH(1 ether);
        assertEq(WETH9.balanceOf(tsmAddr), 1 ether, "wrapped eq");
        assertEq(tsmAddr.balance, 9 ether);

        tsm.exposed_unwrapETH(1 ether);
        assertEq(WETH9.balanceOf(tsmAddr), 0 ether);
        assertEq(tsmAddr.balance, 10 ether);
    }

    function test_V2SwapExactIn() public {
        uint256 ethIn = 0.5 ether;
        uint256 usdtOut = (((tsm.getV2PairPrice(WETH, USDT) * ethIn) / 1e18) *
            99) / 100;
        vm.prank(trader);
        tsm.swapV2ExactIn(WETH, USDT, ethIn, usdtOut);
    }

    function test_V3SwapExactIn() public {
        uint256 ethIn = 0.3 ether;
        uint256 usdtOut = (((tsm.getV3PairPrice(WETH, USDT) * ethIn) / 1e18) *
            99) / 100;
        vm.prank(trader);
        tsm.swapV3ExactIn(WETH, USDT, ethIn, usdtOut);
    }

    function test_withdraw() public {
        uint256 ethIn = 1 ether;
        uint256 usdtOut = (((tsm.getV3PairPrice(WETH, USDT) * ethIn) / 1e18) *
            99) / 100;
        vm.prank(trader);
        tsm.swapV3ExactIn(WETH, USDT, ethIn, usdtOut);
        vm.deal(owner, 0);
        vm.prank(owner);
        tsm.withdrawTokensWithUnwrapIfNecessary(WETH);
        assertGt(owner.balance, 0);
        assertEq(IERC20(USDT).balanceOf(owner), 0);
        vm.prank(owner);
        tsm.withdrawTokensWithUnwrapIfNecessary(USDT);
        assertGt(IERC20(USDT).balanceOf(owner), 0);
    }
}
