// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CompensationModule_Integration_Test } from "test/integration/CompensationModule.t.sol";
import { Errors } from "src/modules/compensation-module/libraries/Errors.sol";
import { Flow } from "@sablier/flow/src/types/DataTypes.sol";
import { ICompensationModule } from "src/modules/compensation-module/interfaces/ICompensationModule.sol";

contract CancelComponent_Integration_Concrete_Test is CompensationModule_Integration_Test {
    function setUp() public override {
        CompensationModule_Integration_Test.setUp();

        // Make Eve the caller by default in all test suites as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });
    }

    function test_RevertWhen_CompensationComponentNull() public {
        // Expect the call to revert with the {CompensationComponentNull} error
        vm.expectRevert(Errors.CompensationComponentNull.selector);

        // Run the test
        compensationModule.cancelComponent(1, 0);
    }

    function test_RevertWhen_OnlyCompensationPlanSender() public whenComponentNotNull {
        // Expect the call to revert with the {OnlyCompensationPlanSender} error
        vm.expectRevert(Errors.OnlyCompensationPlanSender.selector);

        // Run the test
        compensationModule.cancelComponent(1, 0);
    }

    function test_CancelComponent() public whenComponentNotNull {
        // Create the calldata for the `cancelComponent` call
        bytes memory data = abi.encodeWithSelector(compensationModule.cancelComponent.selector, 1, 0);

        // Expect the {CompensationComponentCancelled} event to be emitted
        vm.expectEmit();
        emit ICompensationModule.CompensationComponentCancelled(1, 0);

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Retrieve the compensation component status
        uint8 actualStatus = uint8(compensationModule.statusOfComponent(1, 0));

        // Assert the actual and expected status of the compensation component stream
        // The component stream status should be voided as the compensation component has been cancelled
        assertEq(actualStatus, uint8(Flow.Status.VOIDED));
    }
}
