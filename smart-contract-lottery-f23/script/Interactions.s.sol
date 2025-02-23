// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts@1.1.1/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol"; //to get latest deployed contract

contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint256, address) {
        HelperConfig helperConfig = new HelperConfig();
        address _vrfCoordinator = helperConfig.getConfig()._vrfCoordinator; //._vrfCoordinator ==> only returns _vrfCoordinator
        address account = helperConfig.getConfig().account;
        (uint256 subId, ) = createSubscription(_vrfCoordinator, account);
        return (subId, _vrfCoordinator);
    }

    function createSubscription(
        address _vrfCoordinator,
        address account
    ) public returns (uint256, address) {
        console.log("Creating subscription on chain ID: ", block.chainid);
        vm.startBroadcast(account);
        uint256 subId = VRFCoordinatorV2_5Mock(_vrfCoordinator)
            .createSubscription();
        vm.stopBroadcast();

        console.log("Your subscription ID is: ", subId);
        console.log(
            "Please update the subscription ID in your HelperConfig.s.sol"
        );
        return (subId, _vrfCoordinator);
    }

    function run() public {
        createSubscriptionUsingConfig();
    }
}

contract FundSubscription is Script, CodeConstants {
    uint256 public constant FUND_AMOUNT = 3 ether; //3 LINK

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        address _vrfCoordinator = helperConfig.getConfig()._vrfCoordinator;
        uint256 subscriptionId = helperConfig.getConfig().subscriptionId;
        address linkToken = helperConfig.getConfig().link;
        address account = helperConfig.getConfig().account;
        fundSubscription(_vrfCoordinator, subscriptionId, linkToken, account);
    }

    function fundSubscription(
        address _vrfCoordinator,
        uint256 subscriptionId,
        address linkToken,
        address account
    ) public {
        console.log("Funding subscription: ", subscriptionId);
        console.log("Using _vrfCoordinator: ", _vrfCoordinator);
        console.log("On ChainId: ", block.chainid);

        if (block.chainid == LOCAL_CHAIN_ID) {
            vm.startBroadcast();
            VRFCoordinatorV2_5Mock(_vrfCoordinator).fundSubscription(
                subscriptionId,
                FUND_AMOUNT * 100
            );
            vm.stopBroadcast();
        } else {
            vm.startBroadcast(account);
            LinkToken(linkToken).transferAndCall(
                _vrfCoordinator,
                FUND_AMOUNT,
                abi.encode(subscriptionId)
            );
            vm.stopBroadcast();
        }
    }

    function run() public {
        fundSubscriptionUsingConfig();
    }
}

contract AddingConsumer is Script {
    function addingConsumerUsingConfig(address mostRecentlyDeployed) public {
        HelperConfig helperConfig = new HelperConfig();
        uint256 subId = helperConfig.getConfig().subscriptionId;
        address _vrfCoordinator = helperConfig.getConfig()._vrfCoordinator;
        address account = helperConfig.getConfig().account;
        addingConsumer(mostRecentlyDeployed, _vrfCoordinator, subId, account);
    }

    function addingConsumer(
        address contractToAddToVrf,
        address _vrfCoordinator,
        uint256 subId,
        address account
    ) public {
        console.log("Adding consumer contract: ", contractToAddToVrf);
        console.log("To _vrfCoordinator: ", _vrfCoordinator);
        console.log("On ChainId: ", block.chainid);
        vm.startBroadcast(account);
        VRFCoordinatorV2_5Mock(_vrfCoordinator).addConsumer(
            subId,
            contractToAddToVrf
        ); //SubscriptionAPI.sol file addConsumer function
        vm.stopBroadcast();
    }

    function run() external {
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment(
            "Raffle",
            block.chainid
        );
        addingConsumerUsingConfig(mostRecentlyDeployed);
    }
}
