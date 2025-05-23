// SPDX-License-Identifier: MIT

// Handler will narrow down the fuzzing to a specific function

pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {DSCEngine} from "@/src/DSCEngine.sol";
import {DecentralizedStableCoin} from "@/src/DecentralizedStableCoin.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "chainlink-brownie-contracts/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract StopOnRevertHandler is Test {
    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;

    ERC20Mock public weth;
    ERC20Mock public wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    // address[] public usersWithCollateralDeposited;

    uint256 public timesMintIsCalled = 0;
    uint256 public timesRedeemCollateralIsCalled = 0;

    address public currentUser = address(0);
    ERC20Mock public currentCollateral = ERC20Mock(address(0));

    MockV3Aggregator public btcUSDPriceFeed;
    MockV3Aggregator public ethUSDPriceFeed;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dsce = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        btcUSDPriceFeed = MockV3Aggregator(
            dsce.getCollateralTokenPriceFeed(address(weth))
        );
        ethUSDPriceFeed = MockV3Aggregator(
            dsce.getCollateralTokenPriceFeed(address(wbtc))
        );
    }

    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) external {
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        ERC20Mock collateral = _getCCollateralFromSeed(collateralSeed);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender /*address(this)*/, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);
        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();

        // carefull with the double pushing an address. This will happen, but we'll keep ir simple for now
        // usersWithCollateralDeposited.push(msg.sender);
        currentUser = msg.sender;
    }

    function mintDSC(
        uint256 amountCollateral,
        uint256 amountDSCToMint // uint256 addressSeed
    ) external {
        timesMintIsCalled++;
        // if (usersWithCollateralDeposited.length == 0) {
        //     return;
        // }
        // address sender = usersWithCollateralDeposited[
        //     addressSeed % usersWithCollateralDeposited.length
        // ];

        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        (uint256 mintedDSC, uint256 collateralValueInUSD) = dsce
            .getAccountInformation(currentUser);

        uint256 maxMintableDSC = (collateralValueInUSD / 2) - mintedDSC;

        vm.assume(maxMintableDSC > 0);

        amountDSCToMint = bound(amountDSCToMint, 1, maxMintableDSC);

        vm.startPrank(currentUser);
        dsce.mintDSC(amountDSCToMint);
        vm.stopPrank();
    }

    /**
     *
     * @notice THIS BREAKS THE INVARIANT TEST SUITE
     * @dev This is a test function to update the price of the collateral
     *     The known bug would be that if the price of the collateral token drops significantly
     *     in a single block or a short period of time, the entire system could be at risk.
     *     This is a test function to simulate that scenario.
     */
    // function updateCollateralPrice(uint96 _newPrice) external {
    //     int256 newPrice = int256(uint256(_newPrice));
    //     if (currentCollateral == weth) {
    //         ethUSDPriceFeed.updateAnswer(newPrice);
    //     } else if (currentCollateral == wbtc) {
    //         btcUSDPriceFeed.updateAnswer(newPrice);
    //     }
    // }

    ///////////////////////
    //// Helper Functions
    ///////////////////////
    function _getCCollateralFromSeed(
        uint256 collateralSeed
    ) internal returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            currentCollateral = weth;
        } else {
            currentCollateral = wbtc;
        }
        return currentCollateral;
    }
}
