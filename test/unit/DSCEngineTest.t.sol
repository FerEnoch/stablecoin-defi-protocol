// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Mock_ERC20_failedMintDSC} from "@/test/mocks/Mock_ERC20_failedMintDSC.sol";
import {Mock_DSCEngine_failedMintDSC} from "@/test/mocks/Mock_DSCEngine_failedMintDSC.sol";
import {Mock_ERC20_failedTransferFrom} from "@/test/mocks/Mock_ERC20_failedTransferFrom.sol";
import {Mock_DSCEngine_failedTransferFrom} from "@/test/mocks/Mock_DSCEngine_failedTransferFrom.sol";
import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "@/src/DSCEngine.sol";
import {DeployDSC} from "@/script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "@/src/DecentralizedStableCoin.sol";
import {HelperConfig} from "@/script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockV3Aggregator} from "chainlink-brownie-contracts/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC public deployer;
    DSCEngine public dsce;
    HelperConfig public config;
    DecentralizedStableCoin public dsc;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC_BALANCE = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;
    uint256 public constant AMOUNT_COLLATERAL_TO_COVER = 20 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18; // 1.0
    uint256 public constant LIQUIDATION_THRESHOLD = 50; // 50%

    address weth;
    address wbtc;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    uint256 deployerKey;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();

        (weth, wbtc, ethUsdPriceFeed, btcUsdPriceFeed, deployerKey) = config
            .activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_ERC_BALANCE);
    }

    //////////////
    // Constructor tests
    //////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeed() public {
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(ethUsdPriceFeed);

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength
                .selector
        );

        new DSCEngine(tokenAddresses, priceFeedAddresses);
    }

    //////////////
    // Price feed tests
    //////////////

    // won't work in Sepolia forked network
    function testGetUsdValue() public view {
        // 15e18 * 2000e8 = 30000e18
        uint256 ethAmount = 15e18;
        uint256 expectedUsdValue = 30000e18;

        uint256 actualUsdValue = dsce.getUSDValue(weth, ethAmount);
        assertEq(actualUsdValue, expectedUsdValue);

        // 2000e8 * 1e18 = 2000e18
        uint256 ethAmount__2 = 1e18;
        uint256 expectedUsdValue__2 = 2000e18;

        uint256 actualUsdValue__2 = dsce.getUSDValue(weth, ethAmount__2);

        assertEq(actualUsdValue__2, expectedUsdValue__2);
    }

    // won't work in Sepolia forked network
    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 2000 * 1e18;
        uint256 expectedWeth = 1 ether;

        uint256 actualTokenAmount = dsce.getTokenAmountFromUSD(weth, usdAmount);
        assertEq(actualTokenAmount, expectedWeth);

        // 2000 * x / 100 = 100
        // x = 100 * 100 / 2000
        // x = 5 (%)
        // or
        // 100 / 2000 = 0.05
        // 0.05 * 100 = 5 (%)
        usdAmount = 100 * 1e18;
        expectedWeth = 0.05 ether;

        actualTokenAmount = dsce.getTokenAmountFromUSD(weth, usdAmount);
        assertEq(actualTokenAmount, expectedWeth);

        // Test case with eth price dropdown
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(int256(18e8));

        usdAmount = 18 * 1e18;
        expectedWeth = 1 ether;

        actualTokenAmount = dsce.getTokenAmountFromUSD(weth, usdAmount);
        assertEq(actualTokenAmount, expectedWeth);
    }

    //////////////
    // Deposit collateral tests
    //////////////
    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        IERC20(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock();

        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);

        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfTransferFromFails() public {
        address owner = msg.sender;
        vm.prank(owner);

        address mockWETH = address(new Mock_ERC20_failedTransferFrom(owner));
        tokenAddresses = [mockWETH];

        address mockWETHPriceFeed = address(new MockV3Aggregator(8, 2000e8));
        priceFeedAddresses = [mockWETHPriceFeed];

        Mock_DSCEngine_failedTransferFrom mockDsce = new Mock_DSCEngine_failedTransferFrom(
                tokenAddresses,
                priceFeedAddresses
            );

        vm.startPrank(USER);
        IERC20(mockWETH).approve(address(mockDsce), AMOUNT_COLLATERAL);
        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.depositCollateral(mockWETH, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ///////////
    // Modifiers
    //////////

    // This modifier will deposit collateral before running the test
    modifier depositedCollateral() {
        vm.startPrank(USER);
        IERC20(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    // This modifier will deposit collateral and mint DSC before running the test
    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        IERC20(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);

        uint256 amountToMint = AMOUNT_TO_MINT;
        dsce.mintDSC(amountToMint);
        vm.stopPrank();
        _;
    }

    /////////////
    // Deposit collateral tests
    /////////////

    function testCanDepositCollateralWithoutMinting()
        public
        depositedCollateral
    {
        uint256 userWethBalance = dsc.balanceOf(USER);
        assertEq(userWethBalance, 0);
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositedCollateral
    {
        (uint256 totalDebt, uint256 collateralValueInUSD) = dsce
            .getAccountInformation(USER);

        assertEq(totalDebt, 0);
        assertEq(
            AMOUNT_COLLATERAL,
            dsce.getTokenAmountFromUSD(weth, collateralValueInUSD)
        );
        assertEq(
            collateralValueInUSD,
            dsce.getUSDValue(weth, AMOUNT_COLLATERAL)
        );

        assertEq(collateralValueInUSD, dsce.getAccountCollateralValue(USER));
    }

    function test__depositCollateraAndEmitEvent() public {
        /** modifier doesn't being used */
        vm.startPrank(USER);
        IERC20(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectEmit(true, true, false, false, address(dsce));
        emit DSCEngine.CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    //////////////
    // Mint DSC tests
    //////////////

    function testMintDSC() public depositedCollateral {
        uint256 amountToMint = 1 ether;

        vm.startPrank(USER);

        dsce.mintDSC(amountToMint);
        vm.stopPrank();

        // Check health factor
        uint256 healthFactor = dsce.getUserHealthFactor(USER);
        assertGt(healthFactor, 1e18, "Health factor should be greater than 1");

        (uint256 totalDebt, ) = dsce.getAccountInformation(USER);
        assertEq(totalDebt, amountToMint);
    }

    function testRevertsIfMintFails() public {
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];

        Mock_DSCEngine_failedMintDSC mockDsce = new Mock_DSCEngine_failedMintDSC(
                tokenAddresses,
                priceFeedAddresses
            );

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockDsce), AMOUNT_COLLATERAL);
        mockDsce.depositCollateral(weth, AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MintDSCFailed.selector);
        mockDsce.mintDSC(AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testIfMintAmountIsZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDSC(0);
        vm.stopPrank();
    }

    function testMintDSCWithInsufficientCollateral()
        public
        depositedCollateral
    {
        uint256 amountToMint = 10000.1 ether; // Exceeds collateral value

        vm.startPrank(USER);

        vm.expectPartialRevert(
            DSCEngine.DSCEngine__BreaksHealthFactor.selector
        );
        dsce.mintDSC(amountToMint);
        vm.stopPrank();
    }

    function testMintDSCWithExactCollateral() public depositedCollateral {
        uint256 collateralValueInUSD = dsce.getAccountCollateralValue(USER);
        uint256 amountToMint = (collateralValueInUSD * 1e18) / (2 * 1e18); // 200% overcollateralization

        vm.startPrank(USER);
        dsce.mintDSC(amountToMint);
        vm.stopPrank();

        uint256 healthFactor = dsce.getUserHealthFactor(USER);
        assertEq(healthFactor, 1e18);

        (uint256 totalDebt, ) = dsce.getAccountInformation(USER);
        assertEq(totalDebt, amountToMint);
    }

    function testMintDSCWithMultipleCollateralTypes() public {
        vm.startPrank(USER);
        IERC20(wbtc).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(wbtc, AMOUNT_COLLATERAL);

        IERC20(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        uint256 collateralValueInUSD = dsce.getAccountCollateralValue(USER);
        uint256 amountToMint = (collateralValueInUSD * 1e18) / (2 * 1e18); // 200% overcollateralization

        vm.startPrank(USER);
        dsce.mintDSC(amountToMint);
        vm.stopPrank();

        uint256 healthFactor = dsce.getUserHealthFactor(USER);
        assertEq(healthFactor, 1e18);

        (uint256 totalDebt, ) = dsce.getAccountInformation(USER);
        assertEq(totalDebt, amountToMint);

        assertEq(
            collateralValueInUSD,
            dsce.getUSDValue(wbtc, AMOUNT_COLLATERAL) +
                dsce.getUSDValue(weth, AMOUNT_COLLATERAL)
        );
    }

    function testRevertsIfMintedDscBreaksHealthFactor() public {
        (, int256 price, , , ) = MockV3Aggregator(ethUsdPriceFeed)
            .latestRoundData();

        uint256 amountToMint = (AMOUNT_COLLATERAL *
            uint256(price) *
            dsce.getAdditionalFeedPrecision()) / dsce.getPrecision();

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        uint256 expectedHealthFactor = dsce.calculateHealthFactor(
            amountToMint,
            dsce.getUSDValue(weth, AMOUNT_COLLATERAL)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                expectedHealthFactor
            )
        );
        dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    function testDespositCollateralAndMintDSC() public {
        vm.startPrank(USER);
        IERC20(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        dsce.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_TO_MINT
        );
        vm.stopPrank();

        (uint256 totalDebt, ) = dsce.getAccountInformation(USER);
        assertEq(totalDebt, AMOUNT_TO_MINT);
    }

    function testCanMintWithDepositedCollateral()
        public
        depositedCollateralAndMintedDsc
    {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_TO_MINT);
    }

    //////////////
    // Burn DSC tests
    //////////////

    function testBurnDSC() public depositedCollateral {
        uint256 amountToMintAndBurn = 1 ether;

        vm.startPrank(USER);
        dsce.mintDSC(amountToMintAndBurn);

        dsc.approve(address(dsce), amountToMintAndBurn);

        dsce.burnDSC(amountToMintAndBurn);
        vm.stopPrank();

        (uint256 totalDebt, ) = dsce.getAccountInformation(USER);
        assertEq(totalDebt, 0);
    }

    function testCantBurnMoreThanUserHas() public depositedCollateral {
        vm.startPrank(USER);
        dsc.approve(address(dsce), AMOUNT_TO_MINT);

        vm.expectRevert();
        dsce.burnDSC(1 ether);
        vm.stopPrank();
    }

    function testRevertsIfBurnAmountIsZero() public depositedCollateral {
        uint256 amountToMintAndBurn = 1 ether;

        vm.startPrank(USER);
        dsce.mintDSC(amountToMintAndBurn);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDSC(0);
        vm.stopPrank();
    }

    //////////////
    // Redeem collateral tests
    //////////////

    function testRedeemCollateral() public depositedCollateral {
        uint256 amountToMint = 8000 ether;
        uint256 amountCollateralToRedeem = 1 ether;

        vm.startPrank(USER);
        dsce.mintDSC(amountToMint);

        dsce.redeemCollateral(weth, amountCollateralToRedeem);

        vm.stopPrank();

        uint256 healthFactor = dsce.getUserHealthFactor(USER);
        assertGt(
            healthFactor,
            1e18,
            "Health factor should be greater than 1 after redeeming collateral"
        );
        (uint256 totalDebt, ) = dsce.getAccountInformation(USER);
        assertEq(totalDebt, amountToMint);
        assertEq(
            dsce.getAccountCollateralValue(USER),
            dsce.getUSDValue(weth, AMOUNT_COLLATERAL - amountCollateralToRedeem)
        );

        uint256 userWethBalance = IERC20(weth).balanceOf(USER);
        assertEq(amountCollateralToRedeem, userWethBalance);
    }

    function testMustRedeemMoreThanZero()
        public
        depositedCollateralAndMintedDsc
    {
        vm.startPrank(USER);
        dsc.approve(address(dsce), AMOUNT_TO_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateralForDsc(weth, 0, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_TO_MINT
        );
        dsc.approve(address(dsce), AMOUNT_TO_MINT);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    function testRevertsIfRedeemCollateralAndBreakHealthFactor()
        public
        depositedCollateral
    {
        uint256 amountToMint = 8000 ether;
        uint256 amountCollateralToRedeem = 10 ether; // Exceeds collateral value

        vm.startPrank(USER);
        dsce.mintDSC(amountToMint);

        vm.expectPartialRevert(
            DSCEngine.DSCEngine__BreaksHealthFactor.selector
        );
        dsce.redeemCollateral(weth, amountCollateralToRedeem);

        vm.stopPrank();
    }

    function testRedeemCollateralForDsc() public depositedCollateral {
        uint256 amountToMintAndBurn = 6000 ether;
        uint256 amountCollateralToRedeem = 1 ether;

        vm.startPrank(USER);
        dsce.mintDSC(amountToMintAndBurn);

        dsc.approve(address(dsce), amountToMintAndBurn);

        dsce.redeemCollateralForDsc(
            weth,
            amountCollateralToRedeem,
            amountToMintAndBurn
        );
        vm.stopPrank();

        uint256 userDscBalance = dsc.balanceOf(USER);
        (uint256 totalDebt, ) = dsce.getAccountInformation(USER);
        assert((userDscBalance == 0) == (totalDebt == 0));

        uint256 userWethBalance = IERC20(weth).balanceOf(USER);
        assertEq(userWethBalance, amountCollateralToRedeem);
    }

    function testRedeemCollateralForDscRevertsIfBreaksHealthFactor()
        public
        depositedCollateral
    {
        uint256 amountToMint = 8000 ether;
        uint256 amountToBurn = amountToMint - 1 ether;
        uint256 amountCollateralToRedeem = AMOUNT_COLLATERAL; // Exceeds collateral value

        vm.startPrank(USER);
        dsce.mintDSC(amountToMint);

        dsc.approve(address(dsce), amountToMint);

        vm.expectPartialRevert(
            DSCEngine.DSCEngine__BreaksHealthFactor.selector
        );
        dsce.redeemCollateralForDsc(
            weth,
            amountCollateralToRedeem,
            amountToBurn
        );
        vm.stopPrank();
    }

    //////////////
    // Health Factor Tests
    //////////////

    function testProperlyReportHealthFactor()
        public
        depositedCollateralAndMintedDsc
    {
        uint256 expectedHealthFactor = 100 ether;

        (uint256 totalDebt, ) = dsce.getAccountInformation(USER);
        uint256 actualHealthFactor = dsce.calculateHealthFactor(
            totalDebt,
            dsce.getAccountCollateralValue(USER)
        );

        // (20,000 * 50 / 100) * 1e18 = 10,000 * 1e18
        // 10,000 * 1e18 / 100 * 1e18 = 100 * 1e18

        assertEq(actualHealthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne()
        public
        depositedCollateralAndMintedDsc
    {
        int256 ethPriceDropped = 18e8; // ETH price drops to $18
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethPriceDropped);

        uint256 collateralNewValueInUSD = AMOUNT_COLLATERAL *
            uint256(ethPriceDropped * 1e10);
        uint256 thresholdAdjusted = (collateralNewValueInUSD * 50 * 1e18) /
            (100 * 1e18);
        uint256 expectedHealthFactor = thresholdAdjusted / AMOUNT_TO_MINT;
        uint256 actualHealthFactor = dsce.getUserHealthFactor(USER);

        // console.log("actualHealthFactor --> ", actualHealthFactor); // [9e17] || 0.9 ether
        // console.log("expectedHealthFactor --> ", expectedHealthFactor); // [9e17] || 0.9 ether

        assertEq(actualHealthFactor, expectedHealthFactor);
    }

    //////////////
    // Liquidation Tests
    //////////////

    /**
     * @notice -> TITLE: Test Liquidation Scenarios for DSCEngine
     * @notice This test suite simulates various scenarios to verify the liquidation logic of the DSCEngine.
     * It checks when a user's collateralized debt position (CDP) becomes liquidatable based on ETH price fluctuations.
     * * SETUP:
     *  - USER DEPOSIT 10 ether WETH = 1e19 WETH at $2000/ETH ->  20000 USD -> 2e22 USD COLLATERAL
     *  - USER MINT 100 ether DSC = 1e20 DSC -> 1e20 USD DEBT
     * * Initial Collateralization Ratio (CR):
     *  - Collateralization Ratio -> 2e22/1e20 -> (2⋅10^22)/(1⋅10^20) = 2⋅10^2 = 200 (also 20000/100 = 200)
     *    This is a 20,000% CR (200x). This is very high and safe.
     * * Liquidation Parameters:
     *  - The liquidation threshold is set to 50% (2x) in the contract.
     *  - Minimum Collateralization Ratio (MCR) from contract: 200% (or 2.0x).
     *  - Health Factor (HF) = Actual CR / MCR.
     * @dev Scenario 1 -> ETH PRICE DROPS TO $20 USD:
     * * TEST FAILS -> DSCEngine__HealthFactorOk
     * In this case, ETH price drops to exactly the point where CR equals MCR.
     * Test expects liquidation to NOT be possible (health factor is OK).
     *  * Explanation:
     * - ETH PRICE DROPS TO $20
     * - USER COLLATERAL -> 1e19 WETH COLLATERAL at $20/ETH = 2e20 USD -> 200e18 USD
     * - New CR -> 2e20/1e20 -> (2·10^20)/(1·10^20) = 2·10^0 = 2 (also 200/100 = 2).
     *  i.e.:
     *  Scaled: 2e20 / 1e20 = 2.
     *  Nominal: $200 / $100 = 2.
     *  This is a 200% CR (2.0x).
     *  This is a 200% CR (2x)
     * * Liquidation Status:
     *  - Current CR (200%) is EQUAL to MCR (200%).
     *  - Health Factor = 200% / 200% = 1.0.
     *  - Since CR is not strictly less than MCR (or HF is not < 1.0), the user is NOT YET LIQUIDATABLE.
     * * Expected Test Outcome:
     *  - An attempt to liquidate this position should fail.
     *  - With a $20 ETH price, the user is NOT undercollateralized yet, and the test fails
     *   with error "DSCEngine__HealthFactorOk" (This means the test *correctly expects* this revert).
     * @dev Scenario 2 -> ETH PRICE DROPS TO $19.9 USD:
     * * TEST PASSES
     * In this case, ETH price drops just below the point where CR equals MCR.
     * Test expects liquidation to BE possible.
     * * Explanation:
     * - ETH PRICE DROPS TO $19.9
     * - USER COLLATERAL -> 1e19 WETH COLLATERAL at $19.9/ETH = 19.9e19 USD -> 199e18 USD
     * - User's Debt Value: $100 USD (1e20 scaled USD) - remains unchanged.
     * - New CR -> 19.9e19/1e20 -> (19.9·10^19)/(1·10^20) = 19.9·10^−1 = 1.99 (also 199/100 = 1.99).
     *  i.e.:
     *  Scaled: 1.99e20 / 1e20 = 1.99. (Your: (19.9*10^19)/(1*10^20) = 1.99)
     *  Nominal: $199 / $100 = 1.99.
     *  This is a 199% CR (1.99x).
     * * Liquidation Status:
     *  - Current CR (199%) IS LESS THAN MCR (200%).
     *  - Health Factor = 199% / 200% = 0.995.
     *  - Since CR < MCR (or HF < 1.0), the user IS LIQUIDATABLE.
     * * Expected Test Outcome:
     *  - An attempt to liquidate this position should succeed (or a check for `isLiquidatable` should return true).
     */
    /**
     * @dev Conclusion from the above scenarios:
     * Given the user's initial deposit of 10 WETH (1e19 base units) and minted debt of 100 DSC (1e20 base units),
     * and an MCR of 200%:
     * The threshold ETH price at which the position transitions from healthy to liquidatable is $20/ETH.
     * - At $20/ETH: CR = 200%, HF = 1.0 (Not liquidatable by strict < MCR rule).
     * - Below $20/ETH (e.g., $19.999...): CR < 200%, HF < 1.0 (Liquidatable).
     */
    modifier liquidated() {
        int256 ethUsdUpdatedPrice = 19.999e8; // maximum possible ETH price to the user to be successfully liquidated.

        uint256 debtToCover = AMOUNT_TO_MINT; // This is the amount of user's debt the liquidator will cover.

        // USER setup: Deposit collateral and mint DSC
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDSC(weth, AMOUNT_COLLATERAL, debtToCover);
        vm.stopPrank();

        // Simulate price drop to make USER undercollateralized
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        // Now, USER's health factor should be below the minimum.
        // assertLt(dsce.getHealthFactor(USER), dsce.getMinHealthFactor()); // Optional: assert user is liquidatable

        // LIQUIDATOR setup:
        // The liquidator needs to mint `debtToCover` DSC to use for liquidation.
        // Calculate the WETH collateral required for the liquidator to mint `debtToCover` DSC
        // while maintaining a healthy position (e.g., HF = 4, which means 200% collateral for the DSC minted by liquidator,
        // based on how DSCEngine calculates health factor: HF = (CollateralUSD * 2) / DebtDSC (scaled by 1e18).
        // Required Collateral USD for liquidator:
        // -> debtToCover * (LIQUIDATION_PRECISION / LIQUIDATION_THRESHOLD) = debtToCover * (100 / 50) = debtToCover * 2.
        uint256 liquidatorCollateralAmountInDSC = (debtToCover *
            dsce.getLiquidationPrecision()) / dsce.getLiquidationThreshold(); // [2e20]

        uint256 liquidatorCollateralAmountInWETH = dsce.getTokenAmountFromUSD(
            weth,
            liquidatorCollateralAmountInDSC
        ); // [1.005e20]

        // Add 10% delta for rounding issues in liquidator HF.
        // If not, liquidator falls slightly below MCF when trying to mint, and the test
        // reverts with DSCEngine__BreaksHealthFactor(999999999999999999 [9.999e17])
        liquidatorCollateralAmountInWETH +=
            (liquidatorCollateralAmountInWETH * 10) /
            100; // [1.105e20]

        // Mint the calculated WETH amount for the LIQUIDATOR
        ERC20Mock(weth).mint(LIQUIDATOR, liquidatorCollateralAmountInWETH);

        vm.startPrank(LIQUIDATOR);
        // LIQUIDATOR approves the WETH collateral
        ERC20Mock(weth).approve(
            address(dsce),
            liquidatorCollateralAmountInWETH
        );

        // LIQUIDATOR deposits collateral and mints DSC
        dsce.depositCollateralAndMintDSC(
            weth,
            liquidatorCollateralAmountInWETH,
            debtToCover // Liquidator mints the same amount of DSC they will use to cover user's debt
        );

        // LIQUIDATOR approves the DSC to be burned during liquidation
        dsc.approve(address(dsce), debtToCover);

        // LIQUIDATOR liquidates the USER
        dsce.liquidate(USER, weth, debtToCover);
        vm.stopPrank();
        _;
    }

    function testLiquidationAndPayoutBonusCalculation()
        public
        depositedCollateral
    {
        // Calculate max DSC to mint (50% of collateral value)
        // i.e. $20,000 as collateral and 50% of it = $10,000 DSC as debt
        uint256 collateralValueInUsd = dsce.getAccountCollateralValue(USER); // [2e22]
        uint256 maxDscToMint = collateralValueInUsd / 2; // -> (collateralValueInUsd * 50) / 100 --> [1e22]

        /**
         * @notice With this kind of minting and elevated risk (the user is minting max),
         *  the ethPriceDropped is set exactly to the threshold where the liquidated user had enough
         *  collateral to cover the debt and the liquidator will receive a bonus.
         *  If Eth price drops under $1000/ETH, the liquidator will not receive the bonus, and the
         *  expected behaviour of this test is to FAIL.
         */
        int256 ethPriceDropped = 1079e8;

        // Setup user with collateral and debt
        vm.startPrank(USER);
        dsce.mintDSC(maxDscToMint);

        vm.stopPrank();

        // Check -> health factor is exactly 1
        uint256 userHealthFactor = dsce.getUserHealthFactor(USER);
        assertEq(userHealthFactor, 1e18); // assert user is not liquidatable yet

        // Act
        // Now, simulate price drop
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethPriceDropped); // Drop WETH price to $1800

        // Check -> health factor should now be below 1
        userHealthFactor = dsce.getUserHealthFactor(USER);
        assertLt(userHealthFactor, 1e18); // assert user is liquidatable after price drop

        // Setup liquidator
        address liquidator = makeAddr("liquidator");

        // Liquidator Weth balance before liquidation
        uint256 liquidatorWETHBalanceBefore = ERC20Mock(weth).balanceOf(
            liquidator
        );

        (uint256 userDscMinted, ) = dsce.getAccountInformation(USER); // ( [1e22], [1.8e20] )

        // Liquidate total user's position
        uint256 liquidatorNecessaryCollateral = dsce.getTokenAmountFromUSD(
            weth,
            userDscMinted * 2
        );

        // Add 10% delta for rounding issues in health factor
        liquidatorNecessaryCollateral +=
            (liquidatorNecessaryCollateral * 10) /
            100;

        ERC20Mock(weth).mint(liquidator, liquidatorNecessaryCollateral);

        // Liquidate 100% of the user debt
        uint256 debtToCover = userDscMinted;

        vm.startPrank(liquidator);

        ERC20Mock(weth).approve(address(dsce), liquidatorNecessaryCollateral);

        dsce.depositCollateralAndMintDSC(
            weth,
            liquidatorNecessaryCollateral,
            debtToCover
        );

        // Let liquidator approve DSC to cover user's debt
        dsc.approve(address(dsce), debtToCover);

        dsce.liquidate(USER, weth, debtToCover);
        vm.stopPrank();

        // Check -> liquidator's WETH balance after liquidation
        uint256 liquidatorWETHBalanceAfter = ERC20Mock(weth).balanceOf(
            liquidator
        ); // [1e19]

        // Calculate expected liquidator bonus (10%)
        uint256 expectedCollateralReceived = dsce.getTokenAmountFromUSD(
            weth,
            debtToCover
        ); // [5e20]

        uint256 expectedLiquidatorBonus = (expectedCollateralReceived * 10) /
            100;
        uint256 totalExpectedCollateral = expectedCollateralReceived +
            expectedLiquidatorBonus; // [5.5e20]

        /**
         * Verify liquidator received collateral + bonus
         * @notice This verification is done by checking the difference between
         *  liquidator's WETH balance before and after liquidation.
         * @notice THIS ASSERTION ONLY WORKS IF ETH PRICE DOES NOT DROP SIGNIFICANTLY, in order to the liquidator receive
         *  the 10% bonus. If the price drops significantly (i.e. to 20e8), the liquidator's redeemed collateral will
         *  be cropped to the user's debt value (i.e. total value redeemed will be just the collateral value the liquidated user had).
         *  The contract will not pay the liquidator the 10% bonus in this case.
         * @notice In case the bonus is paid, the expected difference should be equal to the total expected collateral
         *  (collateral + bonus).
         * @notice The assertApproxEqAbs function is used to account for small rounding errors
         *  in the calculations.
         * @notice The 2% delta is added to account for rounding errors in the calculations.
         */
        assertApproxEqAbs(
            liquidatorWETHBalanceAfter - liquidatorWETHBalanceBefore,
            totalExpectedCollateral,
            (liquidatorWETHBalanceAfter * 2) / 100 // small 2% delta for rounding errors
        );

        // Verify user's debt decreased
        (uint256 userDscMintedAfter, ) = dsce.getAccountInformation(USER);
        assertEq(userDscMintedAfter, maxDscToMint - debtToCover);
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 debtToCover = AMOUNT_TO_MINT;
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);

        // Threshold for full bonus perception (i.e., payout not capped):
        // The condition for the full bonus perception is: userDebt_USD * 1.1 <= userCollateralValue_USD
        // The "threshold" is the point where the user's collateral is just enough
        // to cover the debt and the full bonus. This occurs when:
        // userDebt_USD * 1.1 = userCollateralValue_USD
        // ETH price should NOT drop to the point where userDebt_USD > (userCollateralValue_USD / 1.1)
        // This means the boundary condition is:
        // userDebt_USD = userCollateralValue_USD * (10/11) -> 10 / 11 \approx 0.90909090...
        // so userDebt_USD approx= userCollateralValue_USD / 100 * 90.91 -> userCollateralValue_USD * 0.9091
        // IN SUMMARY:
        //  Equivalently, the debt is 10/11 (or approximately 90.91%) of the collateral value.
        //  This corresponds to a Collateralization Ratio of 110% or a Loan-to-Value ratio of approximately 90.91%.
        //  Loan-to-Value (LTV): This fraction 10/11 directly represents the LTV ratio.
        //  LTV = userDebt_USD / userCollateralValue_USD = 10/11 As a decimal, 10 / 11 \approx 0.909090... or approximately 90.91%.

        uint256 expectedWeth = dsce.getTokenAmountFromUSD(weth, debtToCover) +
            ((dsce.getTokenAmountFromUSD(weth, debtToCover) *
                dsce.getLiquidationBonus()) / dsce.getLiquidationPrecision());
        // Check if the liquidator received the expected WETH amount ->
        assertEq(liquidatorWethBalance, expectedWeth);
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        // Get how much WETH the user lost
        uint256 amountLiquidated = dsce.getTokenAmountFromUSD(
            weth,
            AMOUNT_TO_MINT
        ) +
            ((dsce.getTokenAmountFromUSD(weth, AMOUNT_TO_MINT) *
                dsce.getLiquidationBonus()) / dsce.getLiquidationPrecision());

        uint256 usdAmountLiquidated = dsce.getUSDValue(weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd = dsce.getUSDValue(
            weth,
            AMOUNT_COLLATERAL
        ) - usdAmountLiquidated;

        (, uint256 userCollateralValueInUsd) = dsce.getAccountInformation(USER);
        assertApproxEqAbs(
            userCollateralValueInUsd,
            expectedUserCollateralValueInUsd,
            (userCollateralValueInUsd * 1) / 100 // small 1% delta for rounding errors
        );
    }

    /**
     * The test confirms that the act of liquidating someone (and thus spending the DSC the liquidator
     * minted for this purpose) does NOT erase the liquidator's own initial minting debt.
     * This is crucial. The liquidator took on a debt to get the DSC, used the DSC, and still owes that
     * initial debt. Their profit comes from the collateral difference.
     */
    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted, ) = dsce.getAccountInformation(
            LIQUIDATOR
        );

        assertEq(liquidatorDscMinted, AMOUNT_TO_MINT);
    }

    function testLiquidatorPaysoffDebtWithoutMintingMoreDSC()
        public
        liquidated
    {
        uint256 liquidatorDscBalance = dsc.balanceOf(LIQUIDATOR);
        // Check if the liquidator's DSC balance before paying off the debt is 0
        assertEq(liquidatorDscBalance, 0);

        uint256 liquidatorWethBalanceBefore = ERC20Mock(weth).balanceOf(
            LIQUIDATOR
        ); // [5.5e18]

        uint256 liquidatorHF = dsce.getUserHealthFactor(LIQUIDATOR); // [1.099e18]
        // assert liquidator is not liquidatable and can operate normally
        assert(liquidatorHF >= MIN_HEALTH_FACTOR);

        // Update ETH PRICE to $50
        int256 ethPriceDropped = 50e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethPriceDropped);

        // Check liquidator's collateral after price hike
        (, uint256 liquidatorCollateralValueLeft) = dsce.getAccountInformation(
            LIQUIDATOR
        );

        address NEW_USER = makeAddr("newUser");
        vm.deal(NEW_USER, STARTING_ERC_BALANCE);
        ERC20Mock(weth).mint(NEW_USER, AMOUNT_COLLATERAL);

        vm.startPrank(NEW_USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDSC(
            weth,
            AMOUNT_COLLATERAL,
            AMOUNT_TO_MINT
        );
        vm.stopPrank();

        uint256 newUserDscBalance = dsc.balanceOf(NEW_USER); // [1e20]
        assertEq(newUserDscBalance, AMOUNT_TO_MINT);

        vm.startPrank(NEW_USER);
        dsc.transfer(LIQUIDATOR, newUserDscBalance);
        vm.stopPrank();

        liquidatorDscBalance = dsc.balanceOf(LIQUIDATOR); // [1e20]
        assertEq(liquidatorDscBalance, AMOUNT_TO_MINT);

        // Now liquidator can pay off the debt with the DSC received from the new user
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(
            address(dsce),
            dsce.getTokenAmountFromUSD(weth, liquidatorCollateralValueLeft)
        );
        dsc.approve(address(dsce), liquidatorDscBalance);
        dsce.redeemCollateralForDsc(
            weth,
            dsce.getTokenAmountFromUSD(weth, liquidatorCollateralValueLeft),
            liquidatorDscBalance
        );
        vm.stopPrank();

        // Check if the liquidator's DSC balance after paying off the debt is 0 again
        liquidatorDscBalance = dsc.balanceOf(LIQUIDATOR);
        assertEq(liquidatorDscBalance, 0);

        // Check the liquidator's protocol information after clearing their position
        (uint256 liquidatorDscMinted, uint256 liquidatorCollateralValue) = dsce
            .getAccountInformation(LIQUIDATOR);
        assertEq(liquidatorDscMinted, 0);
        assertEq(liquidatorCollateralValue, 0);

        // Liquidator's health factor should be max after paying off the debt
        uint256 liquidatorHFAfter = dsce.getUserHealthFactor(LIQUIDATOR);
        assertEq(liquidatorHFAfter, type(uint256).max);

        // Check liquidator's WETH balance after debt payment
        uint256 liquidatorWethBalanceAfter = ERC20Mock(weth).balanceOf(
            LIQUIDATOR
        );
        assertEq(
            liquidatorWethBalanceAfter,
            liquidatorWethBalanceBefore +
                (
                    dsce.getTokenAmountFromUSD(
                        weth,
                        liquidatorCollateralValueLeft
                    )
                )
        );
    }

    ///////////////////////////////////
    // View & Pure Function Tests //
    //////////////////////////////////

    function testGetCollateralTokenPriceFeed() public view {
        address priceFeed = dsce.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, ethUsdPriceFeed);
    }

    function testGetCollateralTokens() public view {
        address[] memory collateralTokens = dsce.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testGetMinHealthFactor() public view {
        uint256 minHealthFactor = dsce.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public view {
        uint256 liquidationThreshold = dsce.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetAccountCollateralValueFromInformation()
        public
        depositedCollateral
    {
        (, uint256 collateralValue) = dsce.getAccountInformation(USER);
        uint256 expectedCollateralValue = dsce.getUSDValue(
            weth,
            AMOUNT_COLLATERAL
        );
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralBalance = dsce.getCollateralBalanceOf(USER, weth);
        assertEq(collateralBalance, AMOUNT_COLLATERAL);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralValue = dsce.getAccountCollateralValue(USER);
        uint256 expectedCollateralValue = dsce.getUSDValue(
            weth,
            AMOUNT_COLLATERAL
        );
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetDSCInstance() public view {
        DecentralizedStableCoin dscAddress = dsce.getDSCInstance();
        assertEq(address(dscAddress), address(dsc));
    }

    function testLiquidationPrecision() public view {
        uint256 expectedLiquidationPrecision = 100;
        uint256 actualLiquidationPrecision = dsce.getLiquidationPrecision();
        assertEq(actualLiquidationPrecision, expectedLiquidationPrecision);
    }
}
