// // SPDX-License-Identifier: MIT

// import {Test, console} from "lib/forge-std/src/Test.sol";
// import {StdInvariant} from "lib/forge-std/src/StdInvariant.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
// import {Handler} from "./Handler.t.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

pragma solidity ^0.8.19;

/*
 *
 * This library is used to check the Chainlink Oracle for stale data
 * If the price is stale the function will revert and render DSCEngine unusable by design
 * We want the DSCEngine top freeze if the prices become stale
 *
 * Nevertheless, known-issue: if the chainlink network explodes, this protocl and the money in it are screwed.
 *
 */
library OracleLib {
    error OracleLib_StalePrice();

    uint256 private constant TIMEOUT = 3 hours; // 3 * 60 * 60 = 10800 seconds

    function staleCheckLatestRoundData(
        AggregatorV3Interface priceFeed
    ) public view returns (uint80, int256, uint256, uint256, uint80) {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) {
            revert OracleLib_StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
