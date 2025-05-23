// SPDX-License-Identifier: MIT

pragma solidity ^0.8.28;

/**
 * @title Open Invariant Test
 * @notice This is an open invariant test for the DSCEngine contract.
 *         THIS WILL NOT WORK IN THIS KIND OF COMPLEX CONTRACT --> every fuzzing reverts
 *         IT'S JUST MEANT TO BE
 *         A DEMO OF HOW TO USE THE INVARIANT TESTS.
 */

/*
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

        // In this open variation of invariant test, we're telling Foundry "go wild on this contract"
        targetContract(address(dsce));
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
*/
