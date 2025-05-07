// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { StationRegistry_Unit_Concrete_Test } from "../StationRegistry.t.sol";
import { Space } from "src/Space.sol";
import { IStationRegistry } from "src/interfaces/IStationRegistry.sol";
import { Errors } from "src/libraries/Errors.sol";

contract CreateAccount_Unit_Concrete_Test is StationRegistry_Unit_Concrete_Test {
    function setUp() public virtual override {
        StationRegistry_Unit_Concrete_Test.setUp();
    }

    modifier whenStationIdZero() {
        _;
    }

    function test_CreateAccount_StationIdZero() external whenStationIdZero {
        // The {StationRegistry} contract deploys each new {Space} contract.
        // Therefore, we need to calculate the current nonce of the {StationRegistry}
        // to pre-compute the address of the new {Space} before deployment.
        (address expectedSpace, bytes memory data) =
            computeDeploymentAddressAndCalldata({ deployer: users.bob, stationId: 0 });

        // Expect the {SpaceCreated} to be emitted
        vm.expectEmit();
        emit IStationRegistry.SpaceCreated({ owner: users.bob, stationId: 1, space: expectedSpace });

        // Make Bob the caller in this test suite
        vm.prank({ msgSender: users.bob });

        // Run the test
        stationRegistry.createAccount({ _admin: users.bob, _data: data });

        // Assert the expected and actual owner of the station
        address actualOwnerOfStation = stationRegistry.ownerOfStation({ stationId: 1 });
        assertEq(users.bob, actualOwnerOfStation);

        // Assert the expected and actual station ID of the {Space}
        uint256 actualStationIdOfSpace = stationRegistry.stationIdOfSpace({ space: expectedSpace });
        assertEq(1, actualStationIdOfSpace);
    }

    modifier whenStationIdNonZero() {
        // Create & deploy a new space with Bob as the owner
        space = deploySpace({ _owner: users.bob, _stationId: 0 });
        _;
    }

    function test_RevertWhen_CallerNotStationOwner() external whenStationIdNonZero {
        // Construct the calldata to be used to initialize the {Space} smart account
        bytes memory data = computeCreateAccountCalldata({ deployer: users.eve, stationId: 1 });

        // Make Eve the caller in this test suite
        vm.prank({ msgSender: users.eve });

        // Expect the {CallerNotStationOwner} to be emitted
        vm.expectRevert(Errors.CallerNotStationOwner.selector);

        // Run the test
        stationRegistry.createAccount({ _admin: users.bob, _data: data });
    }

    modifier whenCallerStationOwner() {
        _;
    }

    function test_CreateAccount_StationIdNonZero() external whenStationIdNonZero whenCallerStationOwner {
        // The {StationRegistry} contract deploys each new {Space} contract.
        // Therefore, we need to calculate the current nonce of the {StationRegistry}
        // to pre-compute the address of the new {Space} before deployment.
        (address expectedSpace, bytes memory data) =
            computeDeploymentAddressAndCalldata({ deployer: users.bob, stationId: 1 });

        // Expect the {SpaceCreated} event to be emitted
        vm.expectEmit();
        emit IStationRegistry.SpaceCreated({ owner: users.bob, stationId: 1, space: expectedSpace });

        // Make Bob the caller in this test suite
        vm.prank({ msgSender: users.bob });

        // Run the test
        stationRegistry.createAccount({ _admin: users.bob, _data: data });

        // Assert if the freshly deployed smart account is registered on the factory
        bool isRegisteredOnFactory = stationRegistry.isRegistered(expectedSpace);
        assertTrue(isRegisteredOnFactory);

        // Assert the expected and actual owner of the station
        address actualOwnerOfStation = stationRegistry.ownerOfStation({ stationId: 1 });
        assertEq(users.bob, actualOwnerOfStation);

        // Assert the expected and actual station ID of the {Space}
        uint256 actualStationIdOfSpace = stationRegistry.stationIdOfSpace({ space: expectedSpace });
        assertEq(1, actualStationIdOfSpace);
    }
}
