// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;
    HelperConfig.NetworkConfig activeConfig;
    ERC20Mock public erc20mock;

    address[] public collateralTokens;
    address[] public priceFeeds;

    address[] public configCollateralTokens;
    address[] public configPriceFeeds;

    address USER = makeAddr("USER");
    address USER2 = makeAddr("USER2");

    uint256 startingBalanceOfUser = 100e8;

    // ERC20 token1 = ERC20(contractCollateralTokens[0]);

    function setUp() public {
        DeployDSC deployDSC = new DeployDSC();
        (dscEngine, dsc, helperConfig) = deployDSC.run();
        (address wethToken, address wbtcToken, address wethPriceFeed, address wbtcPriceFeed,) =
            helperConfig.activeNetworkConfig();
        configCollateralTokens.push(wethToken);
        configCollateralTokens.push(wbtcToken);
        configPriceFeeds.push(wethPriceFeed);
        configPriceFeeds.push(wbtcPriceFeed);

        for (uint256 i = 0; i < configCollateralTokens.length; i++) {
            address collateralAddress = dscEngine.getCollateralTokenAddress(i);
            collateralTokens.push(collateralAddress);
            address priceFeedAddress = dscEngine.getTokenAddressToPriceFeedAddress(collateralAddress);
            priceFeeds.push(priceFeedAddress);
        }

        vm.startPrank(address(deployDSC));
        ERC20Mock(wethToken).transfer(USER, startingBalanceOfUser);
        ERC20Mock(wbtcToken).transfer(USER, startingBalanceOfUser);
        uint256 balanceWeth = ERC20Mock(wethToken).balanceOf(USER);
        uint256 balanceWbtc = ERC20Mock(wbtcToken).balanceOf(USER);
        vm.stopPrank();
        console.log(balanceWeth, balanceWbtc);
    }

    //////////////////////
    // constructor TEST //
    //////////////////////
    function testConstructorParametersAreCorrect() public view {
        assertEq(collateralTokens.length, configCollateralTokens.length);
        assertEq(priceFeeds.length, configPriceFeeds.length);
        assertEq(configCollateralTokens[0], collateralTokens[0]);
        assertEq(configCollateralTokens[1], collateralTokens[1]);
        assertEq(configPriceFeeds[0], priceFeeds[0]);
        assertEq(configPriceFeeds[1], priceFeeds[1]);
        assertEq(address(dsc), address(dscEngine.getDSCCoinAddress()));
    }

    /////////////////////////////
    // depositCollateral TESTs //
    /////////////////////////////
    function testShouldRevertIfZeroAmountOfTokens() public {
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
            dscEngine.depositCollateral(collateralTokens[i], 0);
        }
    }

    function testShouldRevertIfNotAllowedTokenAddress() public {
        address notAllowedTokenAddress = makeAddr("NOTALLOWED");
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(notAllowedTokenAddress, 1);
    }

    function testShouldUpdateTheCollateralDepositedMappingWithOneDeposit() public {
        uint256 amountDeposited = 55e8;

        for (uint256 i = 0; i < collateralTokens.length; i++) {
            assertEq(dscEngine.getCollateralDeposited(USER, collateralTokens[i]), 0);

            vm.startPrank(USER);
            ERC20Mock(collateralTokens[i]).approve(address(dscEngine), amountDeposited);
            dscEngine.depositCollateral(collateralTokens[i], amountDeposited);
            vm.stopPrank();

            assertEq(dscEngine.getCollateralDeposited(USER, collateralTokens[i]), amountDeposited);
        }
    }

    function testShouldUpdateTheCollateralDepositedMappingWithMultipleDeposits() public {
        uint256 firstAmountDeposited = 55e8;
        uint256 secondAmountDeposited = 12e8;

        for (uint256 i = 0; i < collateralTokens.length; i++) {
            assertEq(dscEngine.getCollateralDeposited(USER, collateralTokens[i]), 0);

            vm.startPrank(USER);
            ERC20Mock(collateralTokens[i]).approve(address(dscEngine), firstAmountDeposited + secondAmountDeposited);
            dscEngine.depositCollateral(collateralTokens[i], firstAmountDeposited);
            dscEngine.depositCollateral(collateralTokens[i], secondAmountDeposited);
            vm.stopPrank();

            assertEq(
                dscEngine.getCollateralDeposited(USER, collateralTokens[i]),
                firstAmountDeposited + secondAmountDeposited
            );
        }
    }

    function testShouldDepositCollateralTokensFromCallerToTheDSCEngineContract() public {
        uint256 amountDeposited = 33e8;

        for (uint256 i = 0; i < collateralTokens.length; i++) {
            assertEq(ERC20Mock(collateralTokens[i]).balanceOf(USER), startingBalanceOfUser);
            uint256 contractStartingBalance = ERC20Mock(collateralTokens[i]).balanceOf(address(dscEngine));

            vm.startPrank(USER);
            ERC20Mock(collateralTokens[i]).approve(address(dscEngine), amountDeposited);
            dscEngine.depositCollateral(collateralTokens[i], amountDeposited);
            vm.stopPrank();

            assertEq(ERC20Mock(collateralTokens[i]).balanceOf(USER), startingBalanceOfUser - amountDeposited);
            assertEq(
                ERC20Mock(collateralTokens[i]).balanceOf(address(dscEngine)), contractStartingBalance + amountDeposited
            );
        }
    }

    //////////////////////
    // getUSDValue TEST //
    //////////////////////
    function testGetUSDValue() public view {
        uint256 usdValueWETH = dscEngine.getUSDValue(collateralTokens[0], 1);
        uint256 usdValueWBTC = dscEngine.getUSDValue(collateralTokens[1], 1);
        assert(usdValueWETH == 4000);
        assert(usdValueWBTC == 70000);
        console.log("usdValueWETH: ", usdValueWETH);
        console.log("usdValueWBTC: ", usdValueWBTC);
    }
}
