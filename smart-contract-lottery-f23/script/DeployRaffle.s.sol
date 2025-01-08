// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddingConsumer} from "script/Interactions.s.sol";

contract DeployRaffle is Script {
    function run() public {
        deployContract();
    }

    function deployContract() public returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        // Create subscription
        if (config.subscriptionId == 0) {}
        CreateSubscription subscriptionContract = new CreateSubscription();
        (config.subscriptionId, config._vrfCoordinator) = subscriptionContract
            .createSubscription(config._vrfCoordinator, config.account);

        // Fund subscription
        FundSubscription fundSubscription = new FundSubscription();
        fundSubscription.fundSubscription(
            config._vrfCoordinator,
            config.subscriptionId,
            config.link,
            config.account
        );
        vm.startBroadcast(config.account);
        Raffle raffle = new Raffle(
            config.entranceFee,
            config.interval,
            config._vrfCoordinator,
            config.gasLane,
            config.subscriptionId,
            config.callbackGasLimit
        );
        vm.stopBroadcast();

        AddingConsumer addingConsumer = new AddingConsumer();
        addingConsumer.addingConsumer(
            address(raffle),
            config._vrfCoordinator,
            config.subscriptionId,
            config.account
        );
        return (raffle, helperConfig);
    }
}
