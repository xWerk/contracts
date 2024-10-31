// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { StationRegistry } from "./../../../../src/StationRegistry.sol";
import { Base_Test } from "../../../Base.t.sol";
import { Constants } from "../../../utils/Constants.sol";

contract Constructor_StationRegistry_Test is Base_Test {
    function setUp() public virtual override {
        Base_Test.setUp();
    }

    function test_Constructor() external {
        // Run the test
        new StationRegistry({ _initialAdmin: users.admin, _entrypoint: entrypoint, _moduleKeeper: moduleKeeper });

        // Assert the actual and expected {ModuleKeeper} address
        address actualModuleKeeper = address(stationRegistry.moduleKeeper());
        assertEq(actualModuleKeeper, address(moduleKeeper));

        // Assert the actual and expected {DEFAULT_ADMIN_ROLE} user
        address actualInitialAdmin = stationRegistry.getRoleMember(Constants.DEFAULT_ADMIN_ROLE, 0);
        assertEq(actualInitialAdmin, users.admin);

        // Assert the actual and expected {Entrypoint} address
        address actualEntrypoint = stationRegistry.entrypoint();
        assertEq(actualEntrypoint, address(entrypoint));
    }
}
