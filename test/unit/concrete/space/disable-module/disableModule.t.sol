// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Space_Unit_Concrete_Test } from "../Space.t.sol";
import { MockModule } from "../../../../mocks/MockModule.sol";
import { Events } from "../../../../utils/Events.sol";

contract DisableModule_Unit_Concrete_Test is Space_Unit_Concrete_Test {
    function setUp() public virtual override {
        Space_Unit_Concrete_Test.setUp();
    }

    function test_RevertWhen_CallerNotOwner() external {
        // Make Bob the caller for this test suite who is not the owner of the space
        vm.startPrank({ msgSender: users.bob });

        // Expect the next call to revert with the "Account: not admin or EntryPoint." error
        vm.expectRevert("Account: not admin or EntryPoint.");

        // Run the test
        space.disableModule({ module: address(0x1) });
    }

    modifier whenCallerOwner() {
        // Make Eve the caller for the next test suite as she's the owner of the space
        vm.startPrank({ msgSender: users.eve });
        _;
    }

    modifier givenModuleEnabled() {
        // Enable the {MockModule} first
        space.enableModule({ module: address(mockModule) });
        _;
    }

    function test_DisableModule() external whenCallerOwner givenModuleEnabled {
        // Create a new mock module
        MockModule mockModule = new MockModule();

        // Expect the {ModuleDisabled} to be emitted
        vm.expectEmit();
        emit Events.ModuleDisabled({ module: address(mockModule), owner: users.eve });

        // Run the test
        space.disableModule({ module: address(mockModule) });

        // Assert the module enablement state
        bool isModuleEnabled = space.isModuleEnabled({ module: address(mockModule) });
        assertFalse(isModuleEnabled);
    }
}
