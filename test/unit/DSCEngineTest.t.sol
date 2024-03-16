// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract DSCEngineTest is Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;
    HelperConfig.NetworkConfig activeConfig;
    ERC20 public erc20;

    address[] public contractCollateralTokens;
    address[] public contractPriceFeeds;

    address[] public configCollateralTokens;
    address[] public configPriceFeeds;

    address USER = makeAddr("USER");
    address USER2 = makeAddr("USER2");

    // ERC20 token1 = ERC20(contractCollateralTokens[0]);

    function setUp() public {
        DeployDSC deployDSC = new DeployDSC();
        (dscEngine, dsc, helperConfig) = deployDSC.run();
        (address wethToken, address wbtcToken, address wethPriceFeed, address wbtcPriceFeed) =
            helperConfig.activeNetworkConfig();
        configCollateralTokens.push(wethToken);
        configCollateralTokens.push(wbtcToken);
        configPriceFeeds.push(wethPriceFeed);
        configPriceFeeds.push(wbtcPriceFeed);

        for (uint256 i = 0; i < configCollateralTokens.length; i++) {
            address collateralAddress = dscEngine.getCollateralTokenAddress(i);
            contractCollateralTokens.push(collateralAddress);
            address priceFeedAddress = dscEngine.getTokenAddressToPriceFeedAddress(collateralAddress);
            contractPriceFeeds.push(priceFeedAddress);
        }
        // activeConfig = helperConfig.getActiveConfig();
        // // ERC20 erc20 = new ERC20("Wrapped ETH", "WETH");
        // uint256 collateralTokensLength = dscEngine.getCollateralTokenAddressesLenght();
        // token1._mint(USER, 1000);
    }

    function testConstructorParametersAreCorrect() public view {
        assertEq(contractCollateralTokens.length, configCollateralTokens.length);
        assertEq(contractPriceFeeds.length, configPriceFeeds.length);
        assertEq(configCollateralTokens[0], contractCollateralTokens[0]);
        assertEq(configCollateralTokens[1], contractCollateralTokens[1]);
        assertEq(configPriceFeeds[0], contractPriceFeeds[0]);
        assertEq(configPriceFeeds[1], contractPriceFeeds[1]);
        assertEq(address(dsc), address(dscEngine.getDSCCoinAddress()));
    }

    function testGetUSDValue() public view {
        uint256 usdValueWETH = dscEngine.getUSDValue(contractCollateralTokens[0], 1);
        uint256 usdValueWBTC = dscEngine.getUSDValue(contractCollateralTokens[1], 1);
        // assert(usdValueToken1 == 4000);
        // assert(usdValueToken2 == 70000);
        console.log("usdValueWETH: ", usdValueWETH);
        console.log("usdValueWBTC: ", usdValueWBTC);
    }
}
