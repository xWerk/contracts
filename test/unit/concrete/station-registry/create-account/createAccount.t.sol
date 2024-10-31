// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { StationRegistry_Unit_Concrete_Test } from "../StationRegistry.t.sol";
import { Space } from "./../../../../../src/Space.sol";
import { Errors } from "../../../../utils/Errors.sol";
import { Events } from "../../../../utils/Events.sol";

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
        (address expectedWorkspace, bytes memory data) =
            computeDeploymentAddressAndCalldata({ deployer: users.bob, stationId: 0, initialModules: mockModules });

        // Allowlist the mock modules on the {ModuleKeeper} contract from the admin account
        vm.startPrank({ msgSender: users.admin });
        for (uint256 i; i < mockModules.length; ++i) {
            allowlistModule(mockModules[i]);
        }
        vm.stopPrank();

        // Expect the {SpaceCreated} to be emitted
        vm.expectEmit();
        emit Events.SpaceCreated({
            owner: users.bob,
            stationId: 1,
            space: Space(payable(expectedWorkspace)),
            initialModules: mockModules
        });

        // Make Bob the caller in this test suite
        vm.prank({ msgSender: users.bob });

        // Run the test
        stationRegistry.createAccount({ _admin: users.bob, _data: data });

        // Assert the expected and actual owner of the station
        address actualOwnerOfStation = stationRegistry.ownerOfStation({ stationId: 1 });
        assertEq(users.bob, actualOwnerOfStation);

        // Assert the expected and actual station ID of the {Space}
        uint256 actualStationIdOfSpace = stationRegistry.stationIdOfSpace({ space: expectedWorkspace });
        assertEq(1, actualStationIdOfSpace);
    }

    modifier whenStationIdNonZero() {
        // Create & deploy a new space with Eve as the owner
        space = deploySpace({ _owner: users.bob, _spaceId: 0, _initialModules: mockModules });
        _;
    }

    function test_RevertWhen_CallerNotStationOwner() external whenStationIdNonZero {
        // Construct the calldata to be used to initialize the {Space} smart account
        bytes memory data =
            computeCreateAccountCalldata({ deployer: users.eve, stationId: 1, initialModules: mockModules });

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
        (address expectedWorkspace, bytes memory data) =
            computeDeploymentAddressAndCalldata({ deployer: users.bob, stationId: 1, initialModules: mockModules });

        // Allowlist the mock modules on the {ModuleKeeper} contract from the admin account
        vm.startPrank({ msgSender: users.admin });
        for (uint256 i; i < mockModules.length; ++i) {
            allowlistModule(mockModules[i]);
        }
        vm.stopPrank();

        // Expect the {SpaceCreated} event to be emitted
        vm.expectEmit();
        emit Events.SpaceCreated({
            owner: users.bob,
            stationId: 1,
            space: Space(payable(expectedWorkspace)),
            initialModules: mockModules
        });

        // Make Bob the caller in this test suite
        vm.prank({ msgSender: users.bob });

        // Run the test
        stationRegistry.createAccount({ _admin: users.bob, _data: data });

        // Assert if the freshly deployed smart account is registered on the factory
        bool isRegisteredOnFactory = stationRegistry.isRegistered(expectedWorkspace);
        assertTrue(isRegisteredOnFactory);

        // Assert if the initial modules has been enabled on the {Space} smart account instance
        bool isModuleEnabled = Space(payable(expectedWorkspace)).isModuleEnabled(mockModules[0]);
        assertTrue(isModuleEnabled);

        // Assert the expected and actual owner of the station
        address actualOwnerOfStation = stationRegistry.ownerOfStation({ stationId: 1 });
        assertEq(users.bob, actualOwnerOfStation);

        // Assert the expected and actual station ID of the {Space}
        uint256 actualStationIdOfSpace = stationRegistry.stationIdOfSpace({ space: expectedWorkspace });
        assertEq(1, actualStationIdOfSpace);
    }
}
