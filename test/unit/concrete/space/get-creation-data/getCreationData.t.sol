// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Space_Unit_Concrete_Test } from "../Space.t.sol";

contract GetCreationSalt_Unit_Concrete_Test is Space_Unit_Concrete_Test {
    function setUp() public virtual override {
        Space_Unit_Concrete_Test.setUp();
    }

    function test_GetCreationSalt() external view {
        // Create the expected salt value
        bytes memory expectedCreationData = abi.encode(uint256(0));

        // Assert the creation salt matches the expected value
        assertEq(space.getCreationData(), expectedCreationData);
    }
}
