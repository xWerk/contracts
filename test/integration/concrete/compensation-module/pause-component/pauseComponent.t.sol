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

    function test_RevertWhen_ComponentNull() public {
        // Expect the call to revert with the {ComponentNull} error
        vm.expectRevert(Errors.ComponentNull.selector);

        // Run the test
        compensationModule.pauseComponent({ componentId: 1 });
    }

    function test_RevertWhen_OnlyComponentSender() public whenComponentNotNull {
        // Expect the call to revert with the {OnlyComponentSender} error
        vm.expectRevert(Errors.OnlyComponentSender.selector);

        // Run the test
        compensationModule.pauseComponent({ componentId: 1 });
    }

    function test_GivenComponentNotFunded_PauseComponent()
        public
        whenComponentNotNull
        whenCallerComponentSender(users.eve)
    {
        // Create the calldata for the `pauseComponent` call
        bytes memory data = abi.encodeWithSelector(compensationModule.pauseComponent.selector, 1);

        // Expect the {ComponentPaused} event to be emitted
        vm.expectEmit();
        emit ICompensationModule.ComponentPaused({ componentId: 1 });

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Retrieve the compensation component
        uint8 actualStatus = uint8(compensationModule.statusOfComponent({ componentId: 1 }));

        // Assert the actual and expected status of the compensation component stream
        // The component stream status should be solvent as the total debt is not exceeding the stream balance
        assertEq(actualStatus, uint8(Flow.Status.PAUSED_SOLVENT));
    }

    function test_GivenComponentPartiallyFunded_PauseComponent()
        public
        whenComponentNotNull
        whenCallerComponentSender(users.eve)
        whenComponentPartiallyFunded
    {
        // Create the calldata for the `pauseComponent` call
        bytes memory data = abi.encodeWithSelector(compensationModule.pauseComponent.selector, 1);

        // Expect the {ComponentPaused} event to be emitted
        vm.expectEmit();
        emit ICompensationModule.ComponentPaused({ componentId: 1 });

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Retrieve the compensation component status
        uint8 actualStatus = uint8(compensationModule.statusOfComponent({ componentId: 1 }));

        // Assert the actual and expected status of the compensation component stream
        // The component stream status should be insolvent as the total debt is exceeding the stream balance
        assertEq(actualStatus, uint8(Flow.Status.PAUSED_INSOLVENT));
    }
}
