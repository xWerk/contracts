// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { StationRegistry_Unit_Concrete_Test } from "../StationRegistry.t.sol";
import { ISpace } from "src/interfaces/ISpace.sol";
import { IStationRegistry } from "src/interfaces/IStationRegistry.sol";

contract UpdateSpaceImplementation_Unit_Concrete_Test is StationRegistry_Unit_Concrete_Test {
    function setUp() public virtual override {
        StationRegistry_Unit_Concrete_Test.setUp();
    }

    function test_RevertWhen_CallerNotRegistryOwner() external {
        // Make Bob the caller for this test suite who is not the owner of the registry
        vm.startPrank({ msgSender: users.bob });

        // Expect the next call to revert with the {OwnableUnauthorizedAccount} error
        vm.expectRevert(
            abi.encodeWithSelector(bytes4(keccak256(bytes("OwnableUnauthorizedAccount(address)"))), users.bob)
        );

        // Run the test
        stationRegistry.updateSpaceImplementation({ newSpaceImplementation: ISpace(address(0x1)) });
    }

    modifier whenCallerRegistryOwner() {
        // Make Admin the caller for the next test suite
        vm.startPrank({ msgSender: users.admin });
        _;
    }

    function test_UpdateSpaceImplementation() external whenCallerRegistryOwner {
        ISpace newSpaceImplementation = ISpace(address(0x2));

        // Expect the {SpaceImplementationUpdated} to be emitted
        vm.expectEmit();
        emit IStationRegistry.SpaceImplementationUpdated(newSpaceImplementation);

        // Run the test
        stationRegistry.updateSpaceImplementation(newSpaceImplementation);

        // Assert the actual and expected space implementation address
        address actualSpaceImplementation = stationRegistry.accountImplementation();
        assertEq(actualSpaceImplementation, address(newSpaceImplementation));
    }
}
