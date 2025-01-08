// Arrange
// Act
// Assert

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts@1.1.1/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test, CodeConstants {
    Raffle public raffle;
    HelperConfig public helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address _vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    /* Events */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        _vrfCoordinator = config._vrfCoordinator;
        gasLane = config.gasLane;
        subscriptionId = config.subscriptionId;
        callbackGasLimit = config.callbackGasLimit;

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    /* CHECK ENTERRAFFLE */ ///////////////////////////////////////////////
    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertsWhenYouDontPayEnough() public {
        // Arrange
        vm.prank(PLAYER);
        // Act
        // Assert
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayersWhenTheyEnter() public {
        // Arrange
        vm.prank(PLAYER);
        // Act
        raffle.enterRaffle{value: entranceFee}();
        // Assert
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEnterRaffleEmitsEvent() public {
        // Arrange
        vm.prank(PLAYER);
        // Act
        vm.expectEmit(true, false, false, false, address(raffle)); //we are expecting to emit this event
        emit RaffleEntered(PLAYER); //this is the event to be emitted
        // Assert
        raffle.enterRaffle{value: entranceFee}(); //we will actually do the call
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        // Arrange
        raffle.enterRaffle{value: entranceFee}(); //hasBalance
        vm.warp(block.timestamp + interval + 1); //timeHasPassed: interval - 30 on the anvil blockchain
        vm.roll(block.number + 1); //timeHasPassed
        raffle.performUpkeep("");
        // Act/ Assert
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    /* CHECK UPKEEP */ //////////////////////////////////////////////////

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpKeep("");
        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeppReturnsFalseIfRaffleISNotOpen() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}(); //hasBalance
        vm.warp(block.timestamp + interval + 1); //timeHasPassed: interval - 30 on the anvil blockchain
        vm.roll(block.number + 1); //timeHasPassed
        raffle.performUpkeep("");
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpKeep("");
        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfNotEnoughTimeHasPassed() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval - 1);
        vm.roll(block.number);
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpKeep("");
        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood()
        public
        raffleEntered
    {
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpKeep("");
        // Assert
        assert(upkeepNeeded);
    }

    /* PERFORM UPKEEP */ //////////////////////////////////////////////////

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue()
        public
        raffleEntered
    {
        // Act // Assert
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        currentBalance += entranceFee;
        numPlayers = 1;
        // Act // Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpKeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                rState
            )
        );
        raffle.performUpkeep("");
    }

    modifier raffleEntered() {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    // if we need to get data from emitted events in our tests
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        raffleEntered
    {
        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1]; //entries[0] is going to be from the vrf itself // topic 0 is always reserved for something else
        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0); //typecasting into uint to assure that the requestId is not blank
        assert(uint256(raffleState) == 1);
    }

    //     /// An Ethereum log. Returned by `getRecordedLogs`.
    //     struct Log {
    //     // The topics of the log, including the signature, if any.
    //     bytes32[] topics;
    //     // The raw data of the log.
    //     bytes data;
    //     // The address of the log's emitter.
    //     address emitter;

    /* FULFILLRANDOMWORDS */ //////////////////////////////////////////////////
    modifier skipFork() {
        if(block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformingUpkeep(
        uint256 randomRequestId
    ) public raffleEntered skipFork {
        // Arrange // Act // Assert
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(_vrfCoordinator).fulfillRandomWords( //we can call this function because it is a Mock. In real VRF, only Chainlink can run this function
                randomRequestId,
                address(raffle)
            );
    }

    /* ONE BIG TEST - end to end */
    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        raffleEntered skipFork
    {
        // Arrange
        uint256 additionalEntrances = 3; // 4 total
        uint256 startingIndex = 1;
        address expectedWinner = address(1); //cheated: math done

        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrances;
            i++
        ) {
            address newPlayer = address(uint160(i)); //address(1)/ addres(2))/etc
            hoax(newPlayer, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }
        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 startingBalance = expectedWinner.balance;
        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        VRFCoordinatorV2_5Mock(_vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );
        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalEntrances + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == startingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}

// Arrange
// Act
// Assert
