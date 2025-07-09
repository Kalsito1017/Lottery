//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {HelperConfig, CodeConstants} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
contract CreateSubscription is Script {
    function CreateSubscriptionUsingConfig() public returns (uint256, address) {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        address account = helperConfig.getConfig().account;
        (uint subId, ) = createSubscription(vrfCoordinator, account);
        return (subId, vrfCoordinator);
    }
    function createSubscription(
        address vrfCoordinator,
        address account
    ) public returns (uint256, address) {
        console.log("Creating subscription on chain ID: %d", block.chainid);
        vm.startBroadcast(account);
        uint subId = VRFCoordinatorV2_5Mock(vrfCoordinator)
            .createSubscription();
        vm.stopBroadcast();
        console.log("Subscription created with ID: %d", subId);
        return (subId, vrfCoordinator);
    }

    function run() public {
        // This function is a placeholder for creating a subscription using the configuration.
        // The actual implementation would depend on the specific requirements and the Chainlink VRF setup.
        // For now, we will just call the function to indicate that it should be executed.
        CreateSubscriptionUsingConfig();
    }
}
contract FundSubscription is Script, CodeConstants {
    uint256 public constant FUND_LINK = 3 ether; // Amount of LINK to fund the subscription with
    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        uint256 subscriptionId = helperConfig.getConfig().subscriptionId;
        address linkToken = helperConfig.getConfig().link;
        address account = helperConfig.getConfig().account;
        fundSubscription(vrfCoordinator, subscriptionId, linkToken, account);
    }
    function fundSubscription(
        address vrfCoordinator,
        uint256 subscriptionId,
        address linkToken,
        address account
    ) public {
        console.log("Funding subscription with ID: %d", subscriptionId);
        console.log("Using VRF Coordinator at: %s", vrfCoordinator);
        console.log("On chain ID: %d", block.chainid);
        if (block.chainid == LOCAL_CHAIN_ID) {
            vm.startBroadcast();
            VRFCoordinatorV2_5Mock(vrfCoordinator).fundSubscription(
                subscriptionId,
                FUND_LINK * 10000 // Multiply by 100 for local testing
            );
            vm.stopBroadcast();
        } else {
            vm.startBroadcast();
            LinkToken(linkToken).transferAndCall(
                vrfCoordinator,
                FUND_LINK,
                abi.encode(subscriptionId)
            );

            vm.stopBroadcast();
        }

        VRFCoordinatorV2_5Mock(vrfCoordinator).fundSubscription(
            subscriptionId,
            FUND_LINK
        );
        vm.stopBroadcast();
        console.log("Subscription funded with %d LINK", FUND_LINK);
    }
    function run() public {
        fundSubscriptionUsingConfig();
    }
}

contract AddConsumer is Script {
    function addConsumerUsingConfig(address mostRecentlyDeployed) public {
        HelperConfig helperConfig = new HelperConfig();
        uint256 subId = helperConfig.getConfig().subscriptionId;
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        address account = helperConfig.getConfig().account;
        addConsumer(mostRecentlyDeployed, vrfCoordinator, subId, account);
    }
    function addConsumer(
        address contracttoAddVRF,
        address vrfCoordinator,
        uint256 subId,
        address account
    ) public {
        console.log("Adding consumer contract", contracttoAddVRF);
        console.log("Using VRF Coordinator at: %s", vrfCoordinator);
        console.log("On chain ID: %d", block.chainid);
        vm.startBroadcast(account);
        VRFCoordinatorV2_5Mock(vrfCoordinator).addConsumer(
            subId,
            contracttoAddVRF
        );
        vm.stopBroadcast();
    }
    function run() public {
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment(
            "Raffle",
            block.chainid
        );
        addConsumerUsingConfig(mostRecentlyDeployed);
    }
}
