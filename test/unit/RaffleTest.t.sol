// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {Raffle} from "../../src/Raffle.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployRaffle} from "../../script/DeployRaffe.s.sol";
import {VmSafe} from "lib/forge-std/src/Vm.sol";
import {CodeConstants} from "../../script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
contract RaffleTest is Test, CodeConstants {
    error Raffle_RaffleNotOpen();
    Raffle public raffle;
    HelperConfig public helperConfig;
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;

    address public PLAYER = makeAddr("PLAYER");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;
    function setUp() public {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();

        HelperConfig.NetworkConfig memory config = helperConfig
            .getConfigByChainId(block.chainid);
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);

        // ✅ This is the key missing part
        VRFCoordinatorV2_5Mock(vrfCoordinator).fundSubscription(
            subscriptionId,
            100 ether
        );
    }

    function testRaffleInitiaizesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }
    function testRaffleRevertsWhenYouDontPayEnough() public {
        vm.startPrank(PLAYER);
        vm.expectRevert(Raffle.NotEnoughEth.selector);
        raffle.enterRaffle();
        vm.stopPrank();
    }
    function testRaffleRecordsWhenTheyEnter() public {
        //ARRANGE
        vm.prank(PLAYER);
        // ACT
        raffle.enterRaffle{value: entranceFee}();
        //ASSERT
        address rafflePlayer = raffle.getPlayer(0);
        assert(rafflePlayer == PLAYER);
    }
    function testEnteringRaffleEmitsEvent() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false);
        emit Raffle.RaffleEntered(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }
    function DontAllowPlayerstoEnterWhenRaffleIsCalculating() public {
        // ARRANGE

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        // ACT / ASSERT
        vm.expectRevert(Raffle_RaffleNotOpen.selector);

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }
    function testCheckUpkeepReturnsFalseIfNotEnoughBalance() public {
        // ARRANGE
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        // ACT
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        // ASSERT
        assert(!upkeepNeeded);
    }
    function testCheckUpkeepReturnsFalseIfNotOpen() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Manually call pickWinner to simulate performUpkeep working
        raffle.pickWinner();

        // Assert raffle state is now CALCULATING
        assert(raffle.getRaffleState() == Raffle.RaffleState.CALCULATING);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    //CHALLENGE
    // testCheckUpkeepReturnsFalseIfEnoughTimeHasPasssed
    // testCheckUpkeepReturnsTrueWhenParametersAreGood
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        // ARRANGE
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        // ACT / ASSERT
        raffle.performUpkeep("");
    }
    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        currentBalance = currentBalance + entranceFee;
        numPlayers = 1;

        //ACT / ASSERT
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                raffleState
            )
        );
        raffle.performUpkeep("");
    }
    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        raffleEntered
    {
        // ARRANGE

        vm.recordLogs();
        raffle.performUpkeep("");
        VmSafe.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState raffleState = raffle.getRaffleState();
        // ASSERT
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }
    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }
    function testFullfillRandomnessHappensOnlyAfterPerformUpkeep(
        uint256 randomRequestId
    ) public raffleEntered skipFork {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }
    function testFullfillrandomWordsPicksAWinnerResetsAndSendMoney()
        public
        raffleEntered
        skipFork
    {
        //ARRANGE
        uint256 additionalEntrants = 3; // 4 players total
        uint256 startingIndex = 1;
        address expectedWinner = address(1);
        for (
            uint256 i = startingIndex;
            i < additionalEntrants + startingIndex;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }
        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        //ACT
        vm.recordLogs();
        raffle.performUpkeep("");
        VmSafe.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // ASSERT
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 recentWinnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalEntrants + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0); // RaffleState is OPEN
        assert(recentWinnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}
