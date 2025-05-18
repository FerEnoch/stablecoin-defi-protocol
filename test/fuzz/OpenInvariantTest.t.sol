// SPDX-License-Identifier: MIT
// Have out invariants aka properties
// What are our invariants?

// 1. The total supply of DSC should be always be less than the total value of the collateral in USD.
// 2. Getter view functions should never revert <-- evergreen invariant

pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "@/src/DecentralizedStableCoin.sol";
import {DeployDSC} from "@/script/DeployDSC.s.sol";
import {DSCEngine} from "@/src/DSCEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HelperConfig} from "@/script/HelperConfig.s.sol";

contract OpenInvariantTest is StdInvariant, Test {
    DeployDSC public deployer;
    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;
    HelperConfig public config;
    address public weth;
    address public wbtc;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();

        (weth, wbtc, , , ) = config.activeNetworkConfig();

        targetContract(address(dsce)); // In this open variation of invariant test, we're telling Foundry "go will on this contract"
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWETHDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWBTCDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUSDValue(weth, totalWETHDeposited);
        uint256 wbtcValue = dsce.getUSDValue(wbtc, totalWBTCDeposited);

        // The "equal" assertion is here to work only when wethValue and wbtcValue are 0,
        // that means that the contract has no collateral and no DSC minted.
        assert(wethValue + wbtcValue >= totalSupply);
    }
}
