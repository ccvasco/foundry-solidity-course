// // SPDX-License-Identifier: MIT

// // Invariants:
// // 1. Total supply of DSC should always be less than the total value of collateral

// // 2. Getter view functions should never revert

import {Test, console} from "lib/forge-std/src/Test.sol";
import {StdInvariant} from "lib/forge-std/src/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

pragma solidity ^0.8.19;

contract InvariantTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    Handler handler;
    address weth;
    address wbtc;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (, , weth, wbtc, ) = config.activeNetworkConfig();

        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
        // dont call redeemcollateral unless there is collateral to redeem!! - create a handler to handle how we make calls to the dcs
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        //get value of all collateral and compare it to all debt (dsc)
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("Weth Value: ", wethValue);
        console.log("Wbtc Value: ", wbtcValue);
        console.log("totalSupply: ", totalSupply);
        console.log("Times MintDsc Called: ", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    // function invariant_gettersShouldNotRevert() public view {
    //     //dsce.getPrecision();
    //     //dsce.getLiquidationBonus();
    //     //etc
    // }
}
