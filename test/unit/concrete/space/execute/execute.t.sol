// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Space_Unit_Concrete_Test } from "../Space.t.sol";
import { Errors } from "src/libraries/Errors.sol";
import { MockModule } from "test/mocks/MockModule.sol";

contract Execute_Unit_Concrete_Test is Space_Unit_Concrete_Test {
    function setUp() public virtual override {
        Space_Unit_Concrete_Test.setUp();
    }

    function test_RevertWhen_CallerNotOwner() external {
        // Make Bob the caller for this test suite who is not the owner of the space
        vm.startPrank({ msgSender: users.bob });

        // Expect the next call to revert with the {CallerNotEntryPointOrAdmin} error
        vm.expectRevert(Errors.CallerNotEntryPointOrAdmin.selector);

        // Run the test
        space.execute({ module: address(mockModule), value: 0, data: "" });
    }

    modifier whenCallerOwner() {
        // Make Eve the caller for the next test suite as she's the owner of the space
        vm.startPrank({ msgSender: users.eve });
        _;
    }

    function test_RevertWhen_ModuleNotAllowlisted() external whenCallerOwner {
        // Expect the next call to revert with the {ModuleNotAllowlisted} error
        vm.expectRevert(abi.encodeWithSelector(Errors.ModuleNotAllowlisted.selector, address(0x1)));

        // Run the test by trying to execute a module at `0x0000000000000000000000000000000000000001` address
        space.execute({ module: address(0x1), value: 0, data: "" });
    }

    modifier whenModuleAllowlisted() {
        _;
    }

    function test_Execute() external whenCallerOwner whenModuleAllowlisted {
        // Create the calldata for the mock module execution
        bytes memory data = abi.encodeWithSignature("createModuleItem()", "");

        // Expect the {ModuleItemCreated} event to be emitted
        vm.expectEmit();
        emit MockModule.ModuleItemCreated({ id: 0 });

        // Run the test
        space.execute({ module: address(mockModule), value: 0, data: data });

        // Alter the `createModuleItem` method signature by adding an invalid `uint256` field
        bytes memory wrongData = abi.encodeWithSignature("createModuleItem(uint256)", 1);

        // Expect the call to be reverted due to invalid method signature
        vm.expectRevert();

        // Run the test
        space.execute({ module: address(mockModule), value: 0, data: wrongData });
    }
}
