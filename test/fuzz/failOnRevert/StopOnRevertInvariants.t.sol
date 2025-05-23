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
import {StopOnRevertHandler} from "@/test/fuzz/failOnRevert/StopOnRevertHandler.t.sol";

contract StopOnRevertInvariants is StdInvariant, Test {
    DeployDSC public deployer;
    DSCEngine public dsce;
    DecentralizedStableCoin public DSC;
    HelperConfig public config;
    StopOnRevertHandler public handler;
    address public weth;
    address public wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (DSC, dsce, config) = deployer.run();

        (weth, wbtc, , , ) = config.activeNetworkConfig();

        // Instructions for testing --> we'll user the Handler for this
        handler = new StopOnRevertHandler(dsce, DSC);
        targetContract(address(handler));
        // For example: Hey! Don't call redeemCollateral if there is no collateral to redeem.
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = DSC.totalSupply();
        uint256 totalWETHDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWBTCDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUSDValue(weth, totalWETHDeposited);
        uint256 wbtcValue = dsce.getUSDValue(wbtc, totalWBTCDeposited);

        console.log("wethValue ------>", wethValue);
        console.log("wbtcValue ------>", wbtcValue);
        console.log("totalSupply: ----->", totalSupply);

        console.log(
            "timesMintIsCalled ----------->",
            handler.timesMintIsCalled()
        );
        console.log(
            "timesRedeemCollateralIsCalled ----------->",
            handler.timesRedeemCollateralIsCalled()
        );

        // The "equal" assertion is here to work only when wethValue and wbtcValue are 0,
        // that means that the contract has no collateral and no DSC minted.
        assert(wethValue + wbtcValue >= totalSupply);
    }

    // Getter view functions should never revert <-- evergreen invariant
    // We must include this invariant. To see our check list, run
    // forge inspect DSCEngine methods
    // function invariant_gettersShouldNotRevert() public view {
    //     // This is a test to check that the getter functions do not revert.
    //     dsce.getLiquidationBonus();
    //     dsce.getCollateralTokens();
    // }
}
