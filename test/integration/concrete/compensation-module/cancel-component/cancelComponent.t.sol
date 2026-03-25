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

    function test_RevertWhen_ComponentNull() public {
        // Expect the call to revert with the {ComponentNull} error
        vm.expectRevert(Errors.ComponentNull.selector);

        // Run the test
        compensationModule.cancelComponent({ componentId: 1 });
    }

    function test_RevertWhen_OnlyComponentSender() public whenComponentNotNull {
        // Expect the call to revert with the {OnlyComponentSender} error
        vm.expectRevert(Errors.OnlyComponentSender.selector);

        // Run the test
        compensationModule.cancelComponent({ componentId: 1 });
    }

    function test_CancelComponent()
        public
        whenComponentNotNull
        whenComponentFunded
        whenCallerComponentSender(users.eve)
    {
        // Store the Space's USDT balance before the cancellation
        uint256 balanceBefore = usdt.balanceOf(address(space));

        // Retrieve the refundable amount before the cancellation
        uint128 refundableAmount = compensationModule.refundableAmountOf({ streamId: 1 });

        // Sanity check: there should be a non-zero refundable amount
        assertGt(refundableAmount, 0);

        // Create the calldata for the `cancelComponent` call
        bytes memory data = abi.encodeWithSelector(compensationModule.cancelComponent.selector, 1);

        // Expect the {ComponentCanceled} event to be emitted
        vm.expectEmit();
        emit ICompensationModule.ComponentCanceled({ componentId: 1, refundedAmount: refundableAmount });

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Assert the entire refundable amount has been refunded to the sender's address (the Space)
        uint256 balanceAfter = usdt.balanceOf(address(space));
        assertEq(balanceAfter - balanceBefore, refundableAmount);

        // Retrieve the compensation component status
        uint8 actualStatus = uint8(compensationModule.statusOfComponent({ componentId: 1 }));

        // Assert the actual and expected status of the compensation component stream
        // The component stream status should be voided as the compensation component has been cancelled
        assertEq(actualStatus, uint8(Flow.Status.VOIDED));
    }
}
