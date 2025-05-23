// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author Fer Enoch
 * The system is designed to be as minimal as possible, and have the tokens mantain the peg 1:1 with usd.
 * This stablecoin has the properties of:
 * - Relative Stability: Anchored or Pegged --> $ 1 USD
 * - Stability Mechanism (minting): Algorithmic (Decentralized)
 * - Collateralization Mechanism: Exogenous (Crypto)
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC.
 *
 * Our DSC system should always be "over collateralized".
 * At no point, should the value of all collateral <= the $ backed value of all the DSC
 *
 * @notice This contract is the code of the DSC System. It handles all the logic for mining
 * and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS system (DAI)
 *
 */
contract DSCEngine is ReentrancyGuard {
    ///////////
    // Types
    ///////////
    using OracleLib for AggregatorV3Interface;

    ///////////
    // Errors
    ///////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintDSCFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__NotEnoughCollateralToRedeem(uint256 available);

    ///////////
    // state variables
    ///////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralization
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus
    uint256 private constant LIQUIDATOR_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    ///////////
    // Events
    ///////////
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

    ///////////
    // Modifiers
    ///////////
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) revert DSCEngine__NeedsMoreThanZero();
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    ///////////
    // functions
    ///////////
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = new DecentralizedStableCoin(address(this));
    }

    ///////////
    // external & public functions
    ///////////

    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToMint The amount of DSC to mint
     * @notice This function deposits collateral and mints DSC in a single transaction.
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDscToMint);
    }

    /**
     * @notice follows CEI pattern
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant // when you work with external calls, you should always use nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        // external interactions should always be at last (CEI pattern)
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) revert DSCEngine__TransferFailed();
    }

    /**
     * @param tokenCollateralAddress The address of the token to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of DSC to burn
     * @notice This function burns DSC and redeems underlying collateral in a single transaction.
     */
    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        burnDSC(amountDscToBurn);
        // redeemCollateral function checks health factor
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(
            msg.sender,
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        // CHECK HEALTH FACTOR after collateral pulled
        // (It's an alteration of CEI order, but necessary here)
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI
     * @param amountDscToMint The amount of DSC to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDSC(
        uint256 amountDscToMint
    )
        public
        moreThanZero(amountDscToMint)
        nonReentrant // when you work with external calls, you should always use nonReentrant
    {
        s_DSCMinted[msg.sender] += amountDscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) revert DSCEngine__MintDSCFailed();
    }

    // Essentially, this reduce the debt in the system.
    function burnDSC(uint256 amount) public moreThanZero(amount) {
        _burnDSC(amount, msg.sender, msg.sender);

        _revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit...
    }

    /**
     * @notice Liquidate a user by a liquidator.
     *         If we do start nearing undercollateralization, we need someone to liquidate position.
     *         If we have $100 in ETH backing $50 DSC, and the price of our collateral in ETH drops to $20,
     *         we need to liquidate, because DSC isn't worth $1 (or more, in relation with collateral and its threshold) anymore.
     *         There's some gamification here: If someone is almost undercollateralized, we'll pay you to liquidate them!
     *         The liquidator will take the collateral and burn the DSC.
     *         i.e.: A user has $75 in WETH collateral backing $50 DSC. Their health factor is below the minimum,
     *         making them liquidatable. A liquidator decides to cover the full $50 DSC debt.
     *         The liquidator provides $50 DSC to be burned.
     *         In return, the liquidator receives WETH collateral covering the $50 debt, PLUS a 10% bonus on that amount.
     *         So, they receive WETH worth $50 (for the debt) + WETH worth $5 (10% bonus on $50) = $55 total worth of WETH.
     *         The liquidator's profit is the $5 worth of WETH (the bonus). The user is left with $75 - $55 = $20 of WETH
     *         and 0 DSC debt (assuming full liquidation of the $50 debt).
     * @notice You can partially liquidate a user.
     * @notice You will get a liquidation bonus of 10% for taking the user's funds.
     *         The bonus is calculated as 10% of the collateral value equivalent to the `debtToCover`.
     *         The liquidator receives this bonus *in addition* to the collateral covering the debt portion.
     *         However, the total collateral transferred to the liquidator (`actualCollateralToRedeem`)
     *         is capped at the user's available balance of the specified collateral token.
     *         If a liquidator attempts to cover 100% of the debt, and the user's collateral
     *         is insufficient to cover both the debt portion and the full 10% calculated bonus,
     *         the liquidator will receive all of the user's available collateral for that token.
     *         In such a scenario, the effective bonus received might be less than the initially calculated 10%.
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order
     *         for this to work (for the whole system to work).
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to
     *         incentive the liquidators. For example, if the price of the collateral plummeted before anyone could be liquidated.
     * @notice This function follows the CEI pattern.
     * @param collateral The erc20 collateral address of the token to liquidate
     * @param user The address of the user who has broken the health factor (below MIN_HEALTH_FACTOR)
     * @param debtToCover The amount of DSC you want to burn to improve users health factor.
     *                    This value can be up to 100% of the user's current outstanding DSC debt.
     *                    If `debtToCover` exceeds the user's actual minted DSC at the time of liquidation,
     *                    the transaction will revert due to an arithmetic underflow in the `_burnDSC` function
     *                    when attempting to reduce the user's debt. Liquidators must ensure this value is accurate.
     */
    function liquidate(
        address user,
        address collateral,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);

        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        // We want to burn their DSC debt and take their collateral
        // we pay the debt back in the collateral token
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(
            collateral,
            debtToCover
        );

        // Give them 10% bonus to the liquidator
        // So we are giving the liquidator $110 of WETH for 100 DSC
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATOR_PRECISION;

        uint256 actualCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;

        uint256 userCollateralBalance = s_collateralDeposited[user][collateral];

        if (actualCollateralToRedeem > userCollateralBalance) {
            console.log(
                "Actual collateral to redeem has been capped to user balance ->",
                userCollateralBalance
            );
            actualCollateralToRedeem = userCollateralBalance; // Cap at what the user has
        }

        _redeemCollateral(
            user, // from (on behalf of)
            msg.sender, // to (liquidator)
            collateral, // tokenCollateralAddress
            actualCollateralToRedeem // amountCollateral - use the capped amount if necessary
        );

        // This function does external calls (we're breaking a bit CEI pattern, but necessary here
        // to make the checks after) -> trade-off here
        _burnDSC(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        (uint256 userTotalDscMintedAfterLiquidation, ) = _getAccountInformation(
            user
        );

        // This conditional should improve health factor if debt remains, or set to max if debt is cleared.
        if (
            userTotalDscMintedAfterLiquidation > 0 &&
            endingUserHealthFactor <= startingUserHealthFactor
        ) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        // We check that this process doesn't ruin liquidator health factor
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////
    // private & internal functions
    ///////////

    /**
     * @dev Low-level internal function, do not call unless the function calling it, is
     * checking for health factors being broken.
     * @notice This function transfers the DSC from the user to the contract and then burns it.
     * @param amountDscToBurn The amount of DSC to burn
     * @param onBehalfOf The address of whom the DSC is being burned
     * @param dscFrom The address of the user who is burning the DSC. In case of liquidation,
     *                this is the liquidator address.
     */
    function _burnDSC(
        uint256 amountDscToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;

        bool success = i_dsc.transferFrom(
            dscFrom,
            address(this),
            amountDscToBurn
        );

        // This conditional is hypothetically unreachable
        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        i_dsc.burn(amountDscToBurn);
        // Could it be like just (?):
        // i_dsc.burnFrom(dscFrom, amountDscToBurn);
    }

    /**
     * @notice Redeem collateral for a user.
     * @param from The address of the user whose collateral is being redeemed. --> "on behalf of"
     * @param to The address of the liquidator or beneficiary.
     * @param tokenCollateralAddress The address of the collateral token.
     * @param amountCollateral The amount of collateral to redeem.
     */
    function _redeemCollateral(
        address from,
        address to,
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) private {
        uint256 userCollateralBalance = s_collateralDeposited[from][
            tokenCollateralAddress
        ];

        if (userCollateralBalance < amountCollateral) {
            revert DSCEngine__NotEnoughCollateralToRedeem(
                userCollateralBalance
            );
        }

        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;

        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );

        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) revert DSCEngine__TransferFailed();
    }

    ///////////
    // view & pure functions
    ///////////

    function getUserHealthFactor(address user) public view returns (uint256) {
        return _healthFactor(user);
    }

    function calculateHealthFactor(
        uint256 totalDSCMinted,
        uint256 totalCollateralValueInUSD
    ) public pure returns (uint256) {
        return
            _calculateHealthFactor(totalDSCMinted, totalCollateralValueInUSD);
    }

    function _calculateHealthFactor(
        uint256 totalDSCMinted,
        uint256 totalCollateralValueInUSD
    ) internal pure returns (uint256) {
        if (totalDSCMinted == 0) return type(uint256).max;

        // AAVE --> Health Factor = (Total Collateral Value * Weighted Average Liquidation Threshold) / Total Borrow Value
        //     The health factor measures a borrow position’s stability. A health factor below 1 risks liquidation.
        // So:
        uint256 liquidationThreshold = (LIQUIDATION_THRESHOLD * PRECISION) /
            LIQUIDATION_PRECISION;

        uint256 collateralAdjustedForThreshold = (totalCollateralValueInUSD *
            liquidationThreshold) / PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalDSCMinted;
    }

    function getTokenAmountFromUSD(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );

        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();

        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // Returns the amount of token IN WEI needed to cover the USD amount

        return ((usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralValueInUSD)
    {
        totalDSCMinted = s_DSCMinted[user];
        totalCollateralValueInUSD = getAccountCollateralValue(user);
    }

    /**
     * Returns how close to liquidation the user is
     * @param user The address of the user to check
     */
    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalDSCMinted,
            uint256 totalCollateralValueInUSD
        ) = _getAccountInformation(user);

        return
            _calculateHealthFactor(totalDSCMinted, totalCollateralValueInUSD);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. Check health (enough collateral)
        // AAVE --> The health factor measures a borrow position’s stability. A health factor below 1 risks liquidation.
        // Inspiration -> https://aave.com/docs/concepts/liquidations & https://aavehealth.org/

        // 2. Revert if health factor is too low
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }

        return totalCollateralValueInUSD;
    }

    function getUSDValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        address priceFeedAddress = s_priceFeeds[token];

        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            priceFeedAddress
        );

        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();

        uint256 priceWithDecimalPrecision = uint256(price) *
            ADDITIONAL_FEED_PRECISION;
        return (priceWithDecimalPrecision * amount) / PRECISION;
    }

    function getAccountInformation(
        address user
    )
        public
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralValueInUSD)
    {
        (totalDSCMinted, totalCollateralValueInUSD) = _getAccountInformation(
            user
        );
    }

    function getDSCInstance() external view returns (DecentralizedStableCoin) {
        return i_dsc;
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(
        address token
    ) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getCollateralBalanceOf(
        address user,
        address token
    ) public view returns (uint256) {
        return s_collateralDeposited[user][token];
    }
}
