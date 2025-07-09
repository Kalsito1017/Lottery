// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {VRFConsumerBaseV2Plus} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
/**
 * @title Raffle Contract
 * @author Me
 * @notice This contract is a simple raffle system.
 * @dev Implements Chainlink VRFv2.5
 */

contract Raffle is VRFConsumerBaseV2Plus {
    /* Errors */
    error NotEnoughEth();
    error __TransferFailed();
    error Raffle_RaffleNotOpen();

    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 playersLenght,
        uint256 raffleState
    );
    /* Enums */

    enum RaffleState {
        OPEN,
        CALCULATING
    }

    uint16 private constant REQUEST_CONFIRMATIONS = 3; // Maximum number of players allowed in the raffle
    uint32 private constant NUM_WORDS = 1; // Number of random words to request
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    address payable[] public s_players;
    uint256 private s_lastTimeStamp;
    bytes32 private immutable i_keyHash;
    uint32 private immutable i_callbackGasLimit;
    uint256 private immutable i_subscriptionId;
    address private s_recentWinner;
    RaffleState private s_raffleState;
    /* EVENTS */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RaffleRequestedWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert NotEnoughEth();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle_RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timehasPassed = ((block.timestamp - s_lastTimeStamp) >=
            i_interval);
        bool isOpen = (s_raffleState == RaffleState.OPEN);
        bool hasPlayers = (s_players.length > 0);
        bool hasBalance = (address(this).balance > 0);
        upkeepNeeded = (isOpen && timehasPassed && hasPlayers && hasBalance);
        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });

        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RaffleRequestedWinner(requestId);
    }

    function pickWinner() public {
        if ((block.timestamp - s_lastTimeStamp) < i_interval) {
            revert NotEnoughEth();
        }
        s_raffleState = RaffleState.CALCULATING;
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });

        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RaffleRequestedWinner(requestId);
    }

    function fulfillRandomWords(
        uint256,
        /*requestId*/ uint256[] calldata randomWords
    ) internal override {
        //CHECKS
        //EFFCT
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(recentWinner);
        //INTERACTIONS
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert __TransferFailed();
        }
    }

    function getEntraceFee() external view returns (uint256) {
        return i_entranceFee;
    }
    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }
    function getPlayer(uint256 index) external view returns (address) {
        return s_players[index];
    }
    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
