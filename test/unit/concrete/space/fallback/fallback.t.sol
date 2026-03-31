// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Space_Unit_Concrete_Test } from "../Space.t.sol";
import { ISpace } from "src/interfaces/ISpace.sol";

contract Fallback_Unit_Concrete_Test is Space_Unit_Concrete_Test {
    function setUp() public virtual override {
        Space_Unit_Concrete_Test.setUp();
    }

    function test_Fallback() external {
        // Make Bob the caller for this test suite
        vm.startPrank({ msgSender: users.bob });

        // Retrieve the balance before deposit
        uint256 spaceBalanceBefore = address(space).balance;

        // Expect the {NativeReceived} event to be emitted upon ETH deposit with data
        vm.expectEmit();
        emit ISpace.NativeReceived({ from: users.bob, amount: 1 ether });

        // Run the test
        (bool success,) = address(space).call{ value: 1 ether }("test");
        if (!success) revert();

        // Retrieve the balance after deposit
        uint256 spaceBalanceAfter = address(space).balance;

        // Assert the {Space} contract balance increased by 1 ether
        assertEq(spaceBalanceAfter - spaceBalanceBefore, 1 ether);
    }
}
