// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { ModuleKeeper_Unit_Concrete_Test } from "../ModuleKeeper.t.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IModuleKeeper } from "src/interfaces/IModuleKeeper.sol";
import { MockModule } from "test/mocks/MockModule.sol";

contract RemoveFromAllowlist_Unit_Concrete_Test is ModuleKeeper_Unit_Concrete_Test {
    function setUp() public virtual override {
        ModuleKeeper_Unit_Concrete_Test.setUp();
    }

    function test_RevertWhen_CallerNotOwner() external {
        // Make Bob the caller for this test suite who is not the owner of the space
        vm.startPrank({ msgSender: users.bob });

        // Expect the next call to revert with the {Unauthorized} error
        vm.expectRevert(Errors.Unauthorized.selector);

        // Create a mock modules array to remove from the allowlist
        address[] memory modules = new address[](1);
        modules[0] = address(0x1);

        // Run the test
        moduleKeeper.removeFromAllowlist(modules);
    }

    modifier whenCallerOwner() {
        // Make Admin the caller for the next test suite
        vm.startPrank({ msgSender: users.admin });
        _;
    }

    modifier givenModuleAllowlisted() {
        _;
    }

    function test_AddToAllowlist() external whenCallerOwner givenModuleAllowlisted {
        // Create a mock modules array to remove from the allowlist
        address[] memory modules = new address[](1);
        modules[0] = address(mockModule);

        // Expect the {ModuleRemovedFromAllowlist} event to be emitted
        vm.expectEmit();
        emit IModuleKeeper.ModulesRemovedFromAllowlist({ owner: users.admin, modules: modules });

        // Run the test
        moduleKeeper.removeFromAllowlist(modules);

        // Assert the actual and expected allowlist state of the module
        bool actualIsAllowlisted = moduleKeeper.isAllowlisted({ module: address(mockModule) });
        assertFalse(actualIsAllowlisted);
    }
}
