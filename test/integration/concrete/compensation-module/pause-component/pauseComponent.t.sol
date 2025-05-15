// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CompensationModule_Integration_Test } from "test/integration/CompensationModule.t.sol";
import { Errors } from "src/modules/compensation-module/libraries/Errors.sol";
import { Flow } from "@sablier/flow/src/types/DataTypes.sol";
import { ICompensationModule } from "src/modules/compensation-module/interfaces/ICompensationModule.sol";

contract PauseComponent_Integration_Concrete_Test is CompensationModule_Integration_Test {
    function setUp() public override {
        CompensationModule_Integration_Test.setUp();

        // Make Eve the caller by default in all test suites as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });
    }

    function test_RevertWhen_CompensationComponentNull() public {
        // Expect the call to revert with the {CompensationComponentNull} error
        vm.expectRevert(Errors.CompensationComponentNull.selector);

        // Run the test
        compensationModule.pauseComponent(1, 0);
    }

    function test_RevertWhen_OnlyCompensationPlanSender() public whenComponentNotNull {
        // Expect the call to revert with the {OnlyCompensationPlanSender} error
        vm.expectRevert(Errors.OnlyCompensationPlanSender.selector);

        // Run the test
        compensationModule.pauseComponent(1, 0);
    }

    function test_GivenComponentNotFunded_PauseComponent()
        public
        whenComponentNotNull
        whenCallerCompensationPlanSender
    {
        // Create the calldata for the `pauseComponent` call
        bytes memory data = abi.encodeWithSelector(compensationModule.pauseComponent.selector, 1, 0);

        // Expect the {CompensationComponentPaused} event to be emitted
        vm.expectEmit();
        emit ICompensationModule.CompensationComponentPaused(1, 0);

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Retrieve the compensation plan
        uint8 actualStatus = uint8(compensationModule.statusOfComponent(1, 0));

        // Assert the actual and expected status of the compensation component stream
        // The component stream status should be solvent as the total debt is not exceeding the stream balance
        assertEq(actualStatus, uint8(Flow.Status.PAUSED_SOLVENT));
    }

    function test_GivenComponentPartiallyFunded_PauseComponent()
        public
        whenComponentNotNull
        whenCallerCompensationPlanSender
        whenComponentPartiallyFunded
    {
        // Create the calldata for the `pauseComponent` call
        bytes memory data = abi.encodeWithSelector(compensationModule.pauseComponent.selector, 1, 0);

        // Expect the {CompensationComponentPaused} event to be emitted
        vm.expectEmit();
        emit ICompensationModule.CompensationComponentPaused(1, 0);

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Retrieve the compensation component status
        uint8 actualStatus = uint8(compensationModule.statusOfComponent(1, 0));

        // Assert the actual and expected status of the compensation component stream
        // The component stream status should be insolvent as the total debt is exceeding the stream balance
        assertEq(actualStatus, uint8(Flow.Status.PAUSED_INSOLVENT));
    }
}
