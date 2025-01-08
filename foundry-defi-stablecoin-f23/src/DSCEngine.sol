// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

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

pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/*
 * @title DSCEngine
 * @author not me
 * Designed to be as minimal as possible and have the tokens maintain a 1 token == $1 peg
 *
 * stablecoin properties:
 * 1. Exogenous Collateral
 * 2. Dollar Pegged
 * 3. Algoritmically Stable
 *
 * The DSC System should ALWAYS be over-collateralized.
 *ccc
 * @ this contract is the core of the DSC System.
 * It handles all the logic for mining and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice this contract is very loosely based on the MakerDAO DSS (DAI) system.
 *
 */
contract DSCEngine is ReentrancyGuard {
    ///////////////////
    // Errors
    ///////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    ///////////////////
    // Libraries
    ///////////////////
    using OracleLib for AggregatorV3Interface;

    ///////////////////
    // State Variables
    ///////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeeds; //tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    ///////////////////
    // Events
    ///////////////////
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );

    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

    ///////////////////
    // Modifiers
    ///////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ///////////////////
    // Functions
    ///////////////////

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /////////////////////////
    // External Functions
    /////////////////////////

    /*
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     * @param amountDscToMint the amount of decentralized stablecoin to mint
     * @notice this function will deposit collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
     * @param tokenCollateralAddress address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        // Effects
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );

        // Interactions
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /*
     * @param tokenCollateralAddress The collateral address to redeem
     * @param amountCollateral the amount of collateral to redeem
     * @param amountDscToBurn the amount of DSC to burn
     *
     * This function burns DSC and redeems underlying collateral in one transaction
     *
     */
    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral); //redeem collateral already checks health factor
    }
    // In order to redeem colateral, health factor must be over 1 AFTER collateral pulled
    // CEI: Checks, Effects, Interactions

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // Check if the collateral value > DSC amount.
    // They can pick how much they want to mint.
    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // If someone is under-collateralized, we will pay you to liquidate them!
    /*
     * @param collateral The erc20 collateral address to liquidate from the user
     * @param user The user tho has broken the health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount od DSC you want to burn to improve the users health factor
     * @notice you can partially liquidate a user
     * @notice you will get a liquidation bonus for taking the users funds
     * @notice this function assumes the protocol will be roughly 200% over-collateralized in order for this to work. //IF COLLATERAL IS NOW WORTH LESS THAN DSC, NO-ONE WILL WANT TO LIQUIDATE THE USER TO LOSE MONEY
     * @notice a known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incetve liquidators.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     *
     * Follows CEI: Checks, Effects, Interactions
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        //Check health factor of the user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // Burn their DSC debt and take their Collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            /* how much collateral usd value should one get when burning their DSC? */
            collateral,
            debtToCover
        );
        // And give them a 10% bonus
        // we should add a feature to liquidate in the event the protocol is insolvent (not in this project)
        // and sweep extra amount into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;
        _redeemCollateral(
            collateral,
            totalCollateralToRedeem,
            user,
            msg.sender
        );
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender); // if it worsens the original owner's health factor, it should be reverted as well
    }

    function getHealthFactor(
        address user
    ) external view returns (uint256 healthIndex) {
        uint256 healthStat = _healthFactor(user);
        return healthStat;
    }

    /////////////////////////////////////
    // Public & External View Functions
    /////////////////////////////////////
    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        return ((usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        // Loop through each collateral token, get amount deposited and map it to price to get the USD value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        // price comes with 8dp and amount goes with 18dp. We must adjust the dp in price before multiplying by amount, so that we can divide the whole thing by 1e18
        return
            /*((amount * PRECISION) /(uint256(price) * ADDITIONAL_FEED_PRECISION));*/
            (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION; // (1000 * 1e8 * 1e10) * (1000 * 1e18) */
    }

    ////////////////////////////////
    // Private & Internal Functions
    ////////////////////////////////

    /*
     * @devLow-level internal function. D not call unless function calling it is checking for health factors being broken
     */
    function _burnDsc(
        uint256 amountDscToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        s_DscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(
            dscFrom,
            address(this),
            amountDscToBurn
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
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
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /*
     * Returns how colse to liquidation a user is. If a user goes below 1, then they can get liquidated.
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total Dsc minted
        // total collateral value
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        uint256 healthIndex;
        if (totalDscMinted == 0) {
            healthIndex = (collateralAdjustedForThreshold);
        } else if (totalDscMinted > 0) {
            healthIndex = ((collateralAdjustedForThreshold * PRECISION) /
                totalDscMinted);
        }
        // 1000 USD in ETH * 50 = (50.000 / 100) = 500 -> essentially means that protocol will be 200% over-colateralized // deposits worth 50%
        // 150 USD in ETH * 50 = (7500 / 100) = 75
        return healthIndex;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // Does user have enough collateral? Revert if not.
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getCollateralDeposited(
        address user,
        address token
    ) external view returns (uint256) {
        uint256 colldep = s_collateralDeposited[user][token];
        return colldep;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(
        address user,
        address token
    ) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getCollateralTokenPriceFeed(
        address token
    ) external view returns (address) {
        return s_priceFeeds[token];
    }
}
