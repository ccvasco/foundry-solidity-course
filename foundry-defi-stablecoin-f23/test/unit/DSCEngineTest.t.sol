// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = config
            .activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_ERC20_BALANCE);
    }

    //////////////////////////////////
    ////// Constructor Tests
    //////////////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength
                .selector
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ///////////////////////////
    ////// Price Tests
    ///////////////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15e18 * 2000/ETH = 30.000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, 100 ether);
        assertEq(expectedWeth, actualWeth);
        console.log("actualWeth:", actualWeth, "expectedWeth:", expectedWeth);
    }

    //////////////////////////////////
    ////// Deposit Collateral Tests
    //////////////////////////////////
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock(
            "RAN",
            "RAN",
            USER,
            AMOUNT_COLLATERAL
        );
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo()
        public
        depositedCollateral
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(
            weth,
            collateralValueInUsd
        );
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    //////////////////////////////////
    ////// Redeem Collateral Tests
    //////////////////////////////////
    function testCanDepositCollateralAndMintDsc() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 500 ether);
        vm.stopPrank();
    } //\\\\\\\\\\\\bug\\\\\\\\\\\\\\\\\\\
    //\\\\\\\\\\\\bug\\\\\\\\\\\\\\\\\\\
    //\\\\\\\\\\\\bug\\\\\\\\\\\\\\\\\\\
    //\\\\\\\\\\\\bug\\\\\\\\\\\\\\\\\\\ check mint()

    function testGetAccountCollateralValue() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(btcUsdPriceFeed);

        //uint256 expectedCollateralValue = 0.015 ether;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), (AMOUNT_COLLATERAL));
        dsce.depositCollateral(weth, (AMOUNT_COLLATERAL));
        ERC20Mock(wbtc).approve(address(dsce), (AMOUNT_COLLATERAL));
        dsce.depositCollateral(wbtc, AMOUNT_COLLATERAL);
        vm.stopPrank();

        //uint256 totalCollateralValueInUsd = dsce.getAccountCollateralValue(USER);
        //assertEq(totalCollateralValueInUsd, expectedCollateralValue);
        uint256 expectedUsdValueWETH = 20000e18;
        uint256 expectedUsdValueWBTC = 10000e18;
        uint256 usdValueWeth = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 usdValueWbtc = dsce.getUsdValue(wbtc, AMOUNT_COLLATERAL);
        uint256 userAccount = dsce.getAccountCollateralValue(USER);
        uint256 xpectedUserAccount = expectedUsdValueWETH +
            expectedUsdValueWBTC;
        assertEq(usdValueWeth, expectedUsdValueWETH);
        assertEq(usdValueWbtc, expectedUsdValueWBTC);
        assertEq(userAccount, xpectedUserAccount);
        // uint256 colldep = dsce.getCollateralDeposited(USER, weth);
        // uint256 colldep2 = dsce.getCollateralDeposited(USER, wbtc);
        // console.log(usdValueWeth);
        // console.log(usdValueWbtc);
        // console.log(totalCollateralValueInUsd);
        // console.log(colldep);
        // console.log(colldep2);
    } //\\\\\\\\\\\\bug\\\\\\\\\\\\\\\\\\\
    //\\\\\\\\\\\\bug\\\\\\\\\\\\\\\\\\\
    // getUsdValue() CANNOT RETURN uint256(price) ADDITIONAL_FEED_PRECISION) * amount) / PRECISION; but instead should return return ((amount * PRECISION) /
    // (uint256(price) * ADDITIONAL_FEED_PRECISION))
    //\\\\\\\\\\\\bug\\\\\\\\\\\\\\\\\\\
    //\\\\\\\\\\\\bug\\\\\\\\\\\\\\\\\\\

    //////////////////////////////////
    ////// Mint DSC Tests
    //////////////////////////////////
    function testMintDscFailsIfAmountIsZero() public {
        vm.deal(USER, STARTING_ERC20_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert();
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testAnyoneCanMintShouldFail() public {
        vm.deal(USER, STARTING_ERC20_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert();
        dsce.mintDsc(1 ether);
        vm.stopPrank();
    }

    function testUserShouldBeAbleToMintIfHealthFactorIsOk()
        public
        depositedCollateral
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);
        console.log(totalDscMinted, collateralValueInUsd);
        vm.startPrank(USER);
        dsce.mintDsc(10000 ether);
        vm.stopPrank();
    }

    function testUserWillNOTMintIfHealthFactorIsOk()
        public
        depositedCollateral
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce
            .getAccountInformation(USER);
        console.log(totalDscMinted, collateralValueInUsd);
        vm.startPrank(USER);
        vm.expectRevert();
        dsce.mintDsc(10001 ether);
        vm.stopPrank();
    }

    function testHealthFactor() public depositedCollateral {
        uint256 bef_healthIndex = dsce.getHealthFactor(USER);
        console.log(bef_healthIndex);
        /* */
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.mintDsc(10000 ether);
        //dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 20000 ether);
        vm.stopPrank();

        uint256 aft_healthIndex = dsce.getHealthFactor(USER);
        console.log(aft_healthIndex);
        /////// bug ////////// if totalDscMinted = 0, calculation fails --> refactored
    }

    //function testHealthFactorUpdatesAfterMinting() public {}

    //////////////////////////////////
    ////// Deposit & Mint DSC Tests
    //////////////////////////////////
}
//4000.0000.0000.0000.0000
//0199.9800.0199.9800.0199
