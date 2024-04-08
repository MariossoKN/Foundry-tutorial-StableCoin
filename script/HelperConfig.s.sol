// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Script} from "../lib/forge-std/src/Script.sol";
import {MockV3Aggregator} from "../test/mock/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;
    MockV3Aggregator public wethPriceFeed;
    MockV3Aggregator public wbtcPriceFeed;
    ERC20Mock public wethToken;
    ERC20Mock public wbtcToken;

    uint8 decimals = 8;
    int256 initialAnswerWETH = 4000 * 1e8;
    int256 initialAnswerWBTC = 70000 * 1e8;
    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    struct NetworkConfig {
        address wethToken;
        address wbtcToken;
        address wethPriceFeed;
        address wbtcPriceFeed;
        uint256 deployerKey;
    }

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        } else if (block.chainid == 1) {
            activeNetworkConfig = getMainnetConfig();
        } else {
            activeNetworkConfig = getAnvilConfig();
        }
    }

    function getSepoliaConfig() public view returns (NetworkConfig memory) {
        NetworkConfig memory sepoliaNetworkConfig = NetworkConfig({
            wethToken: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
            wbtcToken: 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c,
            wethPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
        return sepoliaNetworkConfig;
    }

    function getMainnetConfig() public view returns (NetworkConfig memory) {
        NetworkConfig memory mainnetNetworkConfig = NetworkConfig({
            wethToken: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
            wbtcToken: 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c,
            wethPriceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
            wbtcPriceFeed: 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
        return mainnetNetworkConfig;
    }

    function getAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethToken != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast(DEFAULT_ANVIL_PRIVATE_KEY);
        wethPriceFeed = new MockV3Aggregator(decimals, initialAnswerWETH);
        wbtcPriceFeed = new MockV3Aggregator(decimals, initialAnswerWBTC);
        wethToken = new ERC20Mock("Token1", "TKN1", msg.sender, 1000e8);
        wbtcToken = new ERC20Mock("Token2", "TKN2", msg.sender, 1000e8);
        vm.stopBroadcast();

        NetworkConfig memory anvilNetworkConfig = NetworkConfig({
            wethToken: address(wethToken),
            wbtcToken: address(wbtcToken),
            wethPriceFeed: address(wethPriceFeed),
            wbtcPriceFeed: address(wbtcPriceFeed),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
        return anvilNetworkConfig;
    }

    function getActiveConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}
