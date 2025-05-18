// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    HelperConfig private config;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    constructor() {
        config = new HelperConfig();
    }

    function run()
        external
        returns (DecentralizedStableCoin, DSCEngine, HelperConfig)
    {
        (
            address weth,
            address wbtc,
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            uint256 deployerKey
        ) = config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);

        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses);
        // DecentralizedStableCoin DSC = new DecentralizedStableCoin(
        //     address(dscEngine)
        // );
        DecentralizedStableCoin DSC = dscEngine.getDSCInstance();

        // DSC.transferOwnership(address(dscEngine));

        vm.stopBroadcast();

        return (DSC, dscEngine, config);
    }
}
