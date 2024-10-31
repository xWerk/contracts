// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { ModuleKeeper_Unit_Concrete_Test } from "../ModuleKeeper.t.sol";
import { MockModule } from "../../../../mocks/MockModule.sol";
import { Errors } from "../../../../utils/Errors.sol";
import { Events } from "../../../../utils/Events.sol";

contract AddToAllowlist_Unit_Concrete_Test is ModuleKeeper_Unit_Concrete_Test {
    function setUp() public virtual override {
        ModuleKeeper_Unit_Concrete_Test.setUp();
    }

    function test_RevertWhen_CallerNotOwner() external {
        // Make Bob the caller for this test suite who is not the owner of the space
        vm.startPrank({ msgSender: users.bob });

        // Expect the next call to revert with the {Unauthorized} error
        vm.expectRevert(Errors.Unauthorized.selector);

        // Run the test
        moduleKeeper.addToAllowlist({ module: address(0x1) });
    }

    modifier whenCallerOwner() {
        // Make Admin the caller for the next test suite
        vm.startPrank({ msgSender: users.admin });
        _;
    }

    function test_RevertWhen_InvalidZeroCodeModule() external whenCallerOwner {
        // Expect the next call to revert with the {InvalidZeroCodeModule} error
        vm.expectRevert(Errors.InvalidZeroCodeModule.selector);

        // Run the test by trying to execute a module at `0x0000000000000000000000000000000000000001` address
        moduleKeeper.addToAllowlist({ module: address(0x1) });
    }

    modifier whenValidNonZeroCodeModule() {
        _;
    }

    function test_AddToAllowlist() external whenCallerOwner whenValidNonZeroCodeModule {
        // Deploy a new {MockModule} contract to be allowlisted
        MockModule moduleToAllowlist = new MockModule();

        // Expect the {ModuleAllowlisted} event to be emitted
        vm.expectEmit();
        emit Events.ModuleAllowlisted({ owner: users.admin, module: address(moduleToAllowlist) });

        // Run the test
        moduleKeeper.addToAllowlist({ module: address(moduleToAllowlist) });

        // Assert the actual and expected allowlist state of the module
        bool actualIsAllowlisted = moduleKeeper.isAllowlisted({ module: address(moduleToAllowlist) });
        assertTrue(actualIsAllowlisted);
    }
}
