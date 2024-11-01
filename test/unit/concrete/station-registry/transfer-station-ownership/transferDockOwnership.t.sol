// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { StationRegistry_Unit_Concrete_Test } from "../StationRegistry.t.sol";
import { MockModule } from "../../../../mocks/MockModule.sol";
import { Space } from "./../../../../../src/Space.sol";
import { Events } from "../../../../utils/Events.sol";
import { Errors } from "../../../../utils/Errors.sol";

contract TransferStationOwnership_Unit_Concrete_Test is StationRegistry_Unit_Concrete_Test {
    function setUp() public virtual override {
        StationRegistry_Unit_Concrete_Test.setUp();
    }

    modifier givenStationCreated() {
        // Create a new station by creating & deploying a new space
        address[] memory modules = new address[](1);
        modules[0] = address(mockModule);

        space = deploySpace({ _owner: users.eve, _spaceId: 0, _initialModules: modules });
        _;
    }

    function test_RevertWhen_CallerNotOwner() external givenStationCreated {
        // Make Bob the caller for this test suite who is not the owner of the station
        vm.startPrank({ msgSender: users.bob });

        // Expect the next call to revert with the {CallerNotStationOwner} error
        vm.expectRevert(Errors.CallerNotStationOwner.selector);

        // Run the test
        stationRegistry.transferStationOwnership({ stationId: 1, newOwner: users.bob });
    }

    modifier whenCallerOwner() {
        // Make Eve the caller for the next test suite as she's the owner of the station
        vm.startPrank({ msgSender: users.eve });
        _;
    }

    function test_TransferStationOwnership() external givenStationCreated whenCallerOwner {
        // Expect the {StationOwnershipTransferred} to be emitted
        vm.expectEmit();
        emit Events.StationOwnershipTransferred({ stationId: 1, oldOwner: users.eve, newOwner: users.bob });

        // Run the test
        stationRegistry.transferStationOwnership({ stationId: 1, newOwner: users.bob });

        // Assert the actual and expected owner
        address actualOwner = stationRegistry.ownerOfStation({ stationId: 1 });
        assertEq(actualOwner, users.bob);
    }
}
