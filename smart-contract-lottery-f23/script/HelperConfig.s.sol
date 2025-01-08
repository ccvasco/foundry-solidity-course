// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts@1.1.1/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";

abstract contract CodeConstants {
    /* VRF Mock Values */
    uint96 public constant MOCK_BASE_FEE = 0.25 ether;
    uint96 public constant MOCK_GAS_PRICE_LINK = 1e9;
    //LINK / ETH Price
    int256 public constant MOCK_WEI_PER_UNIT_LINK = 4e15;
    // i_gas_price = _gasPrice;
    // i_wei_per_unit_link = _weiPerUnitLink;
    // setConfig();

    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
}

contract HelperConfig is CodeConstants, Script {
    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address _vrfCoordinator;
        bytes32 gasLane;
        uint256 subscriptionId;
        uint32 callbackGasLimit;
        address link;
        address account;
    }

    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfig;

    constructor() {
        networkConfig[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(
        uint256 chainId
    ) public returns (NetworkConfig memory) {
        if (networkConfig[chainId]._vrfCoordinator != address(0)) {
            return networkConfig[chainId];
        } else if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return
            NetworkConfig({
                entranceFee: 0.01 ether,
                interval: 30, // 30 seconds
                _vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B /*https://docs.chain.link/vrf/v2-5/supported-networks*/,
                gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae /*https://docs.chain.link/vrf/v2-5/supported-networks (500 gwei Key Hash)*/,
                subscriptionId: 0,
                callbackGasLimit: 500000 /*500k gas*/,
                link: 0x779877A7B0D9E8603169DdbD7836e478b4624789, /* https://docs.chain.link/resources/link-token-contracts?parent=dataFeeds */
                account: 0xf298d9dbDdc8202Ee36864E6687B630Da2FF9227
            });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (localNetworkConfig._vrfCoordinator != address(0)) {
            return localNetworkConfig;
        }

        // Deploy mocks
        vm.startBroadcast();
        VRFCoordinatorV2_5Mock vrfCoordinatorMock = new VRFCoordinatorV2_5Mock(
            MOCK_BASE_FEE,
            MOCK_GAS_PRICE_LINK,
            MOCK_WEI_PER_UNIT_LINK
        );
        LinkToken linkToken = new LinkToken();
        vm.stopBroadcast();

        localNetworkConfig = NetworkConfig({
            entranceFee: 0.01 ether,
            interval: 30, // 30 seconds
            _vrfCoordinator: address(
                vrfCoordinatorMock
            ) /*https://docs.chain.link/vrf/v2-5/supported-networks*/,
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae /*https://docs.chain.link/vrf/v2-5/supported-networks (500 gwei Key Hash)*/,
            subscriptionId: 0,
            callbackGasLimit: 500000 /*500k gas*/,
            link: address(linkToken),
            account: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38 // DEFAULT_SENDER from Base.sol file
        });
        return localNetworkConfig;
    }
}
