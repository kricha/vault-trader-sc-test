// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {TraderAero, IWETH9} from "../src/TraderAerodrome.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TraderHarness is
    TraderAero(
        0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43,
        0x4200000000000000000000000000000000000006
    )
{
    function exposed_wrapETH(uint256 value) external {
        return _wrapEth(value);
    }

    function exposed_unwrapETH(uint256 value) external {
        return _unwrapEth(value);
    }
}

contract TraderAeroSepoliaTest is Test {
    using SafeERC20 for IERC20;

    TraderHarness public tsm;
    address tsmAddr;

    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;

    IWETH9 WETH9 = IWETH9(WETH);

    address owner = vm.addr(0x1);
    address trader = vm.addr(0x2);

    uint256 userInitBalance = 10000000e6;
    uint256[] values;
    address[] recipients;
    uint256 totalValue = 0;

    function setUp() public {
        uint256 fork = vm.createFork("https://mainnet.base.org");
        vm.selectFork(fork);

        vm.startPrank(owner);
        tsm = new TraderHarness();
        tsmAddr = address(tsm);
        tsm.setSwapper(trader);
        vm.stopPrank();

        vm.label(USDC, "USDC");
        vm.label(WETH, "WETH");

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
        tsm.swapStableExactIn(WETH, USDC, 1, 1);
    }

    function test_wrap_unwrapETH() public {
        tsm.exposed_wrapETH(1 ether);
        assertEq(WETH9.balanceOf(tsmAddr), 1 ether, "wrapped eq");
        assertEq(tsmAddr.balance, 9 ether);

        tsm.exposed_unwrapETH(1 ether);
        assertEq(WETH9.balanceOf(tsmAddr), 0 ether);
        assertEq(tsmAddr.balance, 10 ether);
        tsm.getStablePrice(WETH, USDC, false);
        tsm.getStablePrice(USDC, WETH, false);
    }

    function test_swapStableExactIn() public {
        uint256 ethIn = 0.5 ether;
        uint256 usdcOut = (((tsm.getStablePrice(WETH, USDC, false) * ethIn) /
            1e18) * 99) / 100;
        vm.prank(trader);
        tsm.swapStableExactIn(WETH, USDC, ethIn, usdcOut);

        uint256 usdcIn = 1000 * 1e6;
        uint256 ethOut = (((tsm.getStablePrice(USDC, WETH, false) * usdcIn) /
            1e18) * 95) / 100;

        vm.prank(trader);
        tsm.swapStableExactIn(WETH, USDC, usdcIn * 1e6, ethOut); // ???? 1e6 ???
    }

    function test_withdraw() public {
        uint256 ethIn = 1 ether;
        uint256 usdcOut = 1600;
        vm.prank(trader);
        tsm.swapStableExactIn(WETH, USDC, ethIn, usdcOut);
        vm.deal(owner, 0);
        vm.prank(owner);
        tsm.withdrawTokensWithUnwrapIfNecessary(WETH);
        assertGt(owner.balance, 0);
        assertEq(IERC20(USDC).balanceOf(owner), 0);
        vm.prank(owner);
        tsm.withdrawTokensWithUnwrapIfNecessary(USDC);
        assertGt(IERC20(USDC).balanceOf(owner), 0);
    }
}
