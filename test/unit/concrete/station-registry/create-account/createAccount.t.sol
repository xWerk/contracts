// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { StationRegistry_Unit_Concrete_Test } from "../StationRegistry.t.sol";
import { IStationRegistry } from "src/interfaces/IStationRegistry.sol";

contract CreateAccount_Unit_Concrete_Test is StationRegistry_Unit_Concrete_Test {
    function setUp() public virtual override {
        StationRegistry_Unit_Concrete_Test.setUp();
    }

    function test_CreateAccount() external {
        // The {StationRegistry} contract deploys each new {Space} contract.
        // Therefore, we need to calculate the current nonce of the {StationRegistry}
        // to pre-compute the address of the new {Space} before deployment.
        (address expectedSpace, bytes memory data) = computeDeploymentAddressAndCalldata({ deployer: users.bob });

        // Expect the {SpaceCreated} event to be emitted
        vm.expectEmit();
        emit IStationRegistry.SpaceCreated({ admin: users.bob, space: expectedSpace });

        // Make Bob the caller in this test suite
        vm.prank({ msgSender: users.bob });

        // Run the test
        stationRegistry.createAccount({ _admin: users.bob, _data: data });

        // Assert if the freshly deployed smart account is registered on the factory
        bool isRegisteredOnFactory = stationRegistry.isRegistered(expectedSpace);
        assertTrue(isRegisteredOnFactory);
    }

    function test_CreateAccountReturnsExistingSpace() external {
        bytes memory data = computeCreateAccountCalldata({ deployer: users.bob });

        vm.startPrank({ msgSender: users.bob });
        address firstCall = stationRegistry.createAccount({ _admin: users.bob, _data: data });
        address secondCall = stationRegistry.createAccount({ _admin: users.bob, _data: data });
        vm.stopPrank();

        assertEq(firstCall, secondCall, "Should return existing account on second call");
    }
}
