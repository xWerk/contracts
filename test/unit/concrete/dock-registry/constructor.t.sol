// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { DockRegistry } from "./../../../../src/DockRegistry.sol";
import { Base_Test } from "../../../Base.t.sol";
import { Constants } from "../../../utils/Constants.sol";

contract Constructor_DockRegistry_Test is Base_Test {
    function setUp() public virtual override {
        Base_Test.setUp();
    }

    function test_Constructor() external {
        // Run the test
        new DockRegistry({ _initialAdmin: users.admin, _entrypoint: entrypoint, _moduleKeeper: moduleKeeper });

        // Assert the actual and expected {ModuleKeeper} address
        address actualModuleKeeper = address(dockRegistry.moduleKeeper());
        assertEq(actualModuleKeeper, address(moduleKeeper));

        // Assert the actual and expected {DEFAULT_ADMIN_ROLE} user
        address actualInitialAdmin = dockRegistry.getRoleMember(Constants.DEFAULT_ADMIN_ROLE, 0);
        assertEq(actualInitialAdmin, users.admin);

        // Assert the actual and expected {Entrypoint} address
        address actualEntrypoint = dockRegistry.entrypoint();
        assertEq(actualEntrypoint, address(entrypoint));
    }
}
