// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Script, console} from "../lib/forge-std/src/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;

    address[] tokens;
    address[] priceFeeds;

    function run() public returns (DSCEngine, DecentralizedStableCoin, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethToken, address wbtcToken, address wethPriceFeed, address wbtcPriceFeed) =
            helperConfig.activeNetworkConfig();

        for (uint256 i = 0; i < 2; i++) {
            tokens.push(wethToken);
            tokens.push(wbtcToken);
            priceFeeds.push(wethPriceFeed);
            priceFeeds.push(wbtcPriceFeed);
        }
        vm.startBroadcast();
        dsc = new DecentralizedStableCoin();
        dsce = new DSCEngine(tokens, priceFeeds, dsc);
        vm.stopBroadcast();
        return (dsce, dsc, helperConfig);
    }
}
