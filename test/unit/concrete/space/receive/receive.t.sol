// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Space_Unit_Concrete_Test } from "../Space.t.sol";
import { ISpace } from "src/interfaces/ISpace.sol";

contract Receive_Unit_Concrete_Test is Space_Unit_Concrete_Test {
    function setUp() public virtual override {
        Space_Unit_Concrete_Test.setUp();
    }

    function test_Receive() external {
        // Make Bob the caller for this test suite
        vm.startPrank({ msgSender: users.bob });

        // Retrieve the space balance before the deposit
        uint256 spaceBalanceBefore = address(space).balance;

        // Expect the {NativeReceived} event to be emitted upon ETH deposit
        vm.expectEmit();
        emit ISpace.NativeReceived({ from: users.bob, amount: 1 ether });

        // Run the test
        (bool success,) = address(space).call{ value: 1 ether }("");
        if (!success) revert();

        // Retrieve the space balance after the deposit
        uint256 spaceBalanceAfter = address(space).balance;

        // Assert the {Space} contract balance
        assertEq(spaceBalanceAfter - spaceBalanceBefore, 1 ether);
    }
}
