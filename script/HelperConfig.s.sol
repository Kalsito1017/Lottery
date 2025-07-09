// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Script} from "lib/forge-std/src/Script.sol";
import {VRFCoordinatorV2_5Mock} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";
abstract contract CodeConstants {
    uint96 public MOCK_BASE_FEE = 0.1 ether; // 0.25 LINK
    uint96 public MOCK_GAS_PRICE_LINK = 1e2; // 1 LINK per gas
    int256 public MOCK_WEI_PER_UNIT_LINK = 4e15; // 0.004 LINK per wei
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
}
contract HelperConfig is Script, CodeConstants {
    error HelperConfig__InvalidChainId();
    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 gasLane;
        uint32 callbackGasLimit;
        uint256 subscriptionId;
        address link; // Link token address
        address account; // Account to fund the subscription
    }
    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliETHConfig();
    }
    function getConfigByChainId(
        uint256 chainId
    ) public returns (NetworkConfig memory) {
        if (networkConfigs[chainId].vrfCoordinator != address(0)) {
            return networkConfigs[chainId];
        } else if (chainId == LOCAL_CHAIN_ID) {
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }
    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }
    function getSepoliETHConfig() public pure returns (NetworkConfig memory) {
        return
            NetworkConfig({
                entranceFee: 0.01 ether,
                interval: 30 seconds,
                vrfCoordinator: 0x3C0Ca683b403E37668AE3DC4FB62F4B29B6f7a3e,
                gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
                callbackGasLimit: 500000, // 500,000 gas
                subscriptionId: 0,
                link: 0x326C977E6efc84E512bB9C30f76E30c160eD06FB, // Sepolia LINK token address
                account: 0x71BeB7064D6dA1E27278F3d17F0436E389D7E686
            });
    }
    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (localNetworkConfig.vrfCoordinator != address(0)) {
            return networkConfigs[LOCAL_CHAIN_ID];
        }

        vm.startBroadcast();
        VRFCoordinatorV2_5Mock vrfCoordinator = new VRFCoordinatorV2_5Mock(
            MOCK_BASE_FEE,
            MOCK_GAS_PRICE_LINK,
            MOCK_WEI_PER_UNIT_LINK
        );
        LinkToken linkToken = new LinkToken();
        // Create subscription inside broadcast so msg.sender is owner
        uint256 subscriptionId = vrfCoordinator.createSubscription();
        vm.stopBroadcast();

        localNetworkConfig = NetworkConfig({
            entranceFee: 0.01 ether,
            interval: 30 seconds,
            vrfCoordinator: address(vrfCoordinator),
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            callbackGasLimit: 500000, // 500,000 gas
            subscriptionId: subscriptionId,
            link: address(linkToken),
            account: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38 // Use the script deployer as the account
        });
        networkConfigs[LOCAL_CHAIN_ID] = localNetworkConfig;

        return localNetworkConfig;
    }
}
