// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Box} from "../src/Box.sol";
import {GovToken} from "../src/GovToken.sol";
import {TimeLock} from "../src/TimeLock.sol";

contract MyGovernorTest is Test {
    MyGovernor governor;
    Box box;
    GovToken govToken;
    TimeLock timeLock;

    address public USER = makeAddr("user");
    uint256 public constant INITIAL_SUPPLY = 100 ether;

    address[] proposers;
    address[] executors;
    uint256[] values;
    bytes[] calldatas;
    address[] targets;

    uint256 public constant MIN_DELAY = 3600; // after a vote passes
    uint256 public constant VOTING_DELAY = 1; //HOW MANY BLOCKS TILL A VOTE IS ACTIVE
    uint256 public constant VOTING_PERIOD = 50400;
    
    function setUp() public {
        govToken = new GovToken();
        govToken.mint(USER, INITIAL_SUPPLY);

        vm.startPrank(USER);
        govToken.delegate(USER);
        timeLock = new TimeLock(MIN_DELAY, proposers, executors, USER);
        governor = new MyGovernor(govToken, timeLock);

        bytes32 proposerRole = timeLock.PROPOSER_ROLE();
        bytes32 executorRole = timeLock.EXECUTOR_ROLE();
        bytes32 adminRole = timeLock.TIMELOCK_ADMIN_ROLE();

        timeLock.grantRole(proposerRole, address(governor));
        timeLock.grantRole(executorRole, address(0));
        timeLock.revokeRole(adminRole, USER);
        vm.stopPrank();

        box = new Box();
        box.transferOwnership(address(timeLock));
    }

    function testCantUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 888;
        string memory description = "store 1 in Box";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", valueToStore);
        values.push(0);
        calldatas.push(encodedFunctionCall);
        targets.push(address(box));

        //1.propose to the DAO
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        //2.view the state
        console.log("Proposal State: ", uint256(governor.state(proposalId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY +1);

        console.log("Proposal State: ", uint256(governor.state(proposalId)));

        //2.vote
        string memory reason = "because i want to";

        uint8 voteWay = 1; //voting FOR(yes)
        vm.prank(USER);
        governor.castVoteWithReason(proposalId, voteWay, reason);
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD +1);

        //3.queue the tx
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);
        
        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY +1);

        //4.execute
        governor.execute(targets, values, calldatas, descriptionHash);

        assert(box.getNumber() == valueToStore);
        console.log("Box value: ", box.getNumber());
    }
}