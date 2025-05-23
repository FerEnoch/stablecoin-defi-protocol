// SPDX-License-Identifier: MIT

// Handler will narrow down the fuzzing to a specific function

pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {DSCEngine} from "@/src/DSCEngine.sol";
import {DecentralizedStableCoin} from "@/src/DecentralizedStableCoin.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract ContinueOnRevertHandler is Test {
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

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dsce = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
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

    function redeemCollateral(
        // uint256 collateralSeed,
        uint256 fuzzedTokenAmountInput // Fuzzed input, should represent a token amount
    ) external {
        timesRedeemCollateralIsCalled++;
        // Ensure currentUser and currentCollateral are valid.
        // These are likely set by a previous call (e.g., depositCollateral).
        // If not, they need to be determined here (e.g., using a collateralSeed for currentCollateral).
        vm.assume(address(currentCollateral) != address(0)); // Ensure currentCollateral is initialized
        vm.assume(currentUser != address(0)); // Ensure currentUser is initialized

        uint256 userBalanceOfCurrentToken = dsce.getCollateralBalanceOf(
            currentUser,
            address(currentCollateral)
        );

        // If the user has no balance of this specific token, we can't redeem.
        vm.assume(userBalanceOfCurrentToken > 0);

        (uint256 mintedDSC, ) = dsce.getAccountInformation(currentUser);

        uint256 userHealthFactor = dsce.getUserHealthFactor(currentUser);
        console.log("userHealthFactor: ----------->", userHealthFactor);

        // If no DSC is minted, user can redeem all their specific collateral.
        if (mintedDSC == 0) {
            uint256 amountToRedeem = bound(
                fuzzedTokenAmountInput,
                1,
                userBalanceOfCurrentToken
            );
            if (amountToRedeem > 0) {
                vm.startPrank(currentUser);
                dsce.redeemCollateral(
                    address(currentCollateral),
                    amountToRedeem
                );
                vm.stopPrank();
            }
            return;
        }

        uint256 safeMaxCollateralNeeded = (mintedDSC * 2001) / 1000;
        uint256 maxRedeemableCollateralValueUSD = 0;
        unchecked {
            maxRedeemableCollateralValueUSD =
                userBalanceOfCurrentToken -
                dsce.getTokenAmountFromUSD(
                    address(currentCollateral),
                    safeMaxCollateralNeeded
                );
        }

        if (maxRedeemableCollateralValueUSD == 0) {
            return;
        }

        uint256 collateralToRedeem = bound(
            fuzzedTokenAmountInput,
            1,
            maxRedeemableCollateralValueUSD
        );

        vm.startPrank(currentUser);
        dsce.redeemCollateral(address(currentCollateral), collateralToRedeem);
        vm.stopPrank();
    }

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
