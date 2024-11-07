// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { StationRegistry_Unit_Concrete_Test } from "../StationRegistry.t.sol";
import { ModuleKeeper } from "./../../../../../src/ModuleKeeper.sol";
import { Events } from "../../../../utils/Events.sol";
import { Errors } from "../../../../utils/Errors.sol";
import { Constants } from "../../../../utils/Constants.sol";

contract UpdateModuleKeeper_Unit_Concrete_Test is StationRegistry_Unit_Concrete_Test {
    function setUp() public virtual override {
        StationRegistry_Unit_Concrete_Test.setUp();
    }

    function test_RevertWhen_CallerNotRegistryOwner() external {
        // Make Bob the caller for this test suite who is not the owner of the registry
        vm.startPrank({ msgSender: users.bob });

        // Expect the next call to revert with the {PermissionsUnauthorizedAccount} error
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.PermissionsUnauthorizedAccount.selector,
                users.bob,
                Constants.DEFAULT_ADMIN_ROLE
            )
        );

        // Run the test
        stationRegistry.updateModuleKeeper({ newModuleKeeper: ModuleKeeper(address(0x1)) });
    }

    modifier whenCallerRegistryOwner() {
        // Make Admin the caller for the next test suite
        vm.startPrank({ msgSender: users.admin });
        _;
    }

    function test_UpdateModuleKeeper() external whenCallerRegistryOwner {
        ModuleKeeper newModuleKeeper = ModuleKeeper(address(0x2));

        // Expect the {ModuleKeeperUpdated} to be emitted
        vm.expectEmit();
        emit Events.ModuleKeeperUpdated(newModuleKeeper);

        // Run the test
        stationRegistry.updateModuleKeeper(newModuleKeeper);

        // Assert the actual and expected module keeper address
        address actualModuleKeeper = address(stationRegistry.moduleKeeper());
        assertEq(actualModuleKeeper, address(newModuleKeeper));
    }
}
