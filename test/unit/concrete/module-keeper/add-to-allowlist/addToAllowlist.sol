// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { ModuleKeeper_Unit_Concrete_Test } from "../ModuleKeeper.t.sol";
import { MockModule } from "test/mocks/MockModule.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IModuleKeeper } from "src/interfaces/IModuleKeeper.sol";

contract AddToAllowlist_Unit_Concrete_Test is ModuleKeeper_Unit_Concrete_Test {
    function setUp() public virtual override {
        ModuleKeeper_Unit_Concrete_Test.setUp();
    }

    function test_RevertWhen_CallerNotOwner() external {
        // Make Bob the caller for this test suite who is not the owner of the space
        vm.startPrank({ msgSender: users.bob });

        // Expect the next call to revert with the {Unauthorized} error
        vm.expectRevert(Errors.Unauthorized.selector);

        // Create a mock modules array to add to the allowlist
        address[] memory modules = new address[](1);
        modules[0] = address(0x1);

        // Run the test
        moduleKeeper.addToAllowlist(modules);
    }

    modifier whenCallerOwner() {
        // Make Admin the caller for the next test suite
        vm.startPrank({ msgSender: users.admin });
        _;
    }

    function test_RevertWhen_InvalidZeroCodeModule() external whenCallerOwner {
        // Expect the next call to revert with the {InvalidZeroCodeModule} error
        vm.expectRevert(Errors.InvalidZeroCodeModule.selector);

        // Create a mock modules array to add to the allowlist
        address[] memory modules = new address[](1);
        modules[0] = address(0x01);

        // Run the test
        moduleKeeper.addToAllowlist(modules);
    }

    modifier whenValidNonZeroCodeModule() {
        _;
    }

    function test_AddToAllowlist() external whenCallerOwner whenValidNonZeroCodeModule {
        // Deploy a new {MockModule} contract to be allowlisted
        MockModule moduleToAllowlist = new MockModule();

        // Create a mock modules array to add to the allowlist
        address[] memory modules = new address[](1);
        modules[0] = address(moduleToAllowlist);

        // Expect the {ModuleAllowlisted} event to be emitted
        vm.expectEmit();
        emit IModuleKeeper.ModulesAllowlisted({ owner: users.admin, modules: modules });

        // Run the test
        moduleKeeper.addToAllowlist(modules);

        // Assert the actual and expected allowlist state of the module
        bool actualIsAllowlisted = moduleKeeper.isAllowlisted({ module: address(moduleToAllowlist) });
        assertTrue(actualIsAllowlisted);
    }
}
