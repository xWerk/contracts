// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { ModuleKeeper_Unit_Concrete_Test } from "../ModuleKeeper.t.sol";
import { MockModule } from "../../../../mocks/MockModule.sol";
import { Errors } from "../../../../utils/Errors.sol";
import { Events } from "../../../../utils/Events.sol";

contract RemoveFromAllowlist_Unit_Concrete_Test is ModuleKeeper_Unit_Concrete_Test {
    function setUp() public virtual override {
        ModuleKeeper_Unit_Concrete_Test.setUp();
    }

    function test_RevertWhen_CallerNotOwner() external {
        // Make Bob the caller for this test suite who is not the owner of the space
        vm.startPrank({ msgSender: users.bob });

        // Expect the next call to revert with the {Unauthorized} error
        vm.expectRevert(Errors.Unauthorized.selector);

        // Run the test
        moduleKeeper.removeFromAllowlist({ module: address(0x1) });
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
        // Expect the {ModuleRemovedFromAllowlist} event to be emitted
        vm.expectEmit();
        emit Events.ModuleRemovedFromAllowlist({ owner: users.admin, module: address(mockModule) });

        // Run the test
        moduleKeeper.removeFromAllowlist({ module: address(mockModule) });

        // Assert the actual and expected allowlist state of the module
        bool actualIsAllowlisted = moduleKeeper.isAllowlisted({ module: address(mockModule) });
        assertFalse(actualIsAllowlisted);
    }
}
