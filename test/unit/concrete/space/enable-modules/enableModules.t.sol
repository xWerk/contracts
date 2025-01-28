// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Space_Unit_Concrete_Test } from "../Space.t.sol";
import { MockModule } from "../../../../mocks/MockModule.sol";
import { Events } from "../../../../utils/Events.sol";
import { Errors } from "../../../../utils/Errors.sol";

contract EnableModule_Unit_Concrete_Test is Space_Unit_Concrete_Test {
    function setUp() public virtual override {
        Space_Unit_Concrete_Test.setUp();
    }

    function test_RevertWhen_CallerNotOwner() external {
        // Make Bob the caller for this test suite who is not the owner of the space
        vm.startPrank({ msgSender: users.bob });

        // Expect the next call to revert with the {CallerNotEntryPointOrAdmin} error
        vm.expectRevert(Errors.CallerNotEntryPointOrAdmin.selector);

        // Run the test
        space.enableModules({ modules: mockModules });
    }

    modifier whenCallerOwner() {
        // Make Eve the caller for the next test suite as she's the owner of the space
        vm.startPrank({ msgSender: users.eve });
        _;
    }

    function test_RevertWhen_ModuleNotAllowlisted() external whenCallerOwner {
        // Create a new module that is not allowlisted
        address notAllowlistedModule = address(new MockModule());
        mockModules[0] = notAllowlistedModule;

        // Expect the next call to revert with the {ModuleNotAllowlisted}
        vm.expectRevert(Errors.ModuleNotAllowlisted.selector);

        // Run the test
        space.enableModules({ modules: mockModules });
    }

    modifier whenNonZeroCodeModule() {
        _;
    }

    function test_EnableModule() external whenCallerOwner whenNonZeroCodeModule {
        // Expect the {ModuleEnabled} to be emitted
        vm.expectEmit();
        emit Events.ModuleEnabled({ module: address(mockModule), owner: users.eve });

        // Run the test
        space.enableModules({ modules: mockModules });

        // Assert the module enablement state
        bool isModuleEnabled = space.isModuleEnabled({ module: address(mockModule) });
        assertTrue(isModuleEnabled);
    }
}
