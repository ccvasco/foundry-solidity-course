//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "lib/forge-std/src/Test.sol";
import {DeployOurToken} from "../script/DeployOurToken.s.sol";
import {OurToken} from "../src/OurToken.sol";

contract OurTokenTest is Test {
    OurToken public ourToken;
    DeployOurToken public deployer;

    address bob = makeAddr("bob");
    address alice = makeAddr("alice");
    address charlie = makeAddr("charlie");

    uint256 public constant STARTING_BALANCE = 100 ether;
    uint256 public constant INITIAL_ALLOWANCE = 1000;

    function setUp() public {
        deployer = new DeployOurToken();
        ourToken = deployer.run();

        vm.prank(msg.sender);
        ourToken.transfer(bob, STARTING_BALANCE);
    }

    function testBobBalance() public view {
        assertEq(STARTING_BALANCE, ourToken.balanceOf(bob));
    }

    function testAllowanceWorks() public {
        //bob approves alice to send tokens on her behalf
        vm.prank(bob);
        ourToken.approve(alice, INITIAL_ALLOWANCE);

        uint256 transferAmount = 500;

        vm.prank(alice);
        ourToken.transferFrom(bob, alice, transferAmount);

        assertEq(ourToken.balanceOf(alice), transferAmount);
        assertEq(ourToken.balanceOf(bob), STARTING_BALANCE - transferAmount);
    }
    //////
    function testTransferExceedsAllowance() public {
        // Bob approves Alice for a smaller amount
        vm.prank(bob);
        ourToken.approve(alice, 200);

        // Attempting to transfer more than allowed should fail
        vm.prank(alice);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        ourToken.transferFrom(bob, charlie, 300);
    }

    function testTransferExceedsBalance() public {
        // Attempting to transfer more than Bob's balance should fail
        vm.prank(bob);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        ourToken.transfer(charlie, STARTING_BALANCE + 1);
    }

    function testTransferToZeroAddress() public {
        // Attempting to transfer to the zero address should fail
        vm.prank(bob);
        vm.expectRevert("ERC20: transfer to the zero address");
        ourToken.transfer(address(0), 50);
    }

    function testTransferFromZeroAddress() public {
        // Attempting to transfer from the zero address should fail
        vm.expectRevert("ERC20: transfer from the zero address");
        ourToken.transferFrom(address(0), charlie, 50);
    }
}
