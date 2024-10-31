// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Space_Unit_Concrete_Test } from "../Space.t.sol";
import { Events } from "../../../../utils/Events.sol";

contract Receive_Unit_Concrete_Test is Space_Unit_Concrete_Test {
    function setUp() public virtual override {
        Space_Unit_Concrete_Test.setUp();
    }

    function test_Receive() external {
        // Make Bob the caller for this test suite
        vm.startPrank({ msgSender: users.bob });

        // Expect the {NativeReceived} event to be emitted upon ETH deposit
        vm.expectEmit();
        emit Events.NativeReceived({ from: users.bob, amount: 1 ether });

        // Run the test
        (bool success,) = address(space).call{ value: 1 ether }("");
        if (!success) revert();

        // Assert the {Space} contract balance
        assertEq(address(space).balance, 1 ether);
    }
}
