// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { StationRegistry } from "./../../../../src/StationRegistry.sol";
import { Base_Test } from "../../../Base.t.sol";
import { Constants } from "../../../utils/Constants.sol";
import { IEntryPoint } from "@thirdweb/contracts/prebuilts/account/interface/IEntrypoint.sol";

contract Constructor_StationRegistry_Test is Base_Test {
    function setUp() public virtual override {
        Base_Test.setUp();
    }

    function test_Initialize() external view {
        // Assert the actual and expected {ModuleKeeper} address
        address actualModuleKeeper = address(stationRegistry.moduleKeeper());
        assertEq(actualModuleKeeper, address(moduleKeeper));

        // Assert the actual and expected owner
        address actualInitialAdmin = stationRegistry.owner();
        assertEq(actualInitialAdmin, users.admin);

        // Assert the actual and expected {Entrypoint} address
        address actualEntrypoint = stationRegistry.entrypoint();
        assertEq(actualEntrypoint, address(entrypoint));

        // Assert VERSION is set correctly
        assertEq(stationRegistry.VERSION(), "1.0.0");
    }

    function test_RevertWhen_InitializeTwice() external {
        // Get the account implementation first
        address spaceImpl = stationRegistry.accountImplementation();

        // Expect revert with InvalidInitialization error when trying to initialize again
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        stationRegistry.initialize(users.admin, IEntryPoint(entrypoint), moduleKeeper, spaceImpl);
    }
}
