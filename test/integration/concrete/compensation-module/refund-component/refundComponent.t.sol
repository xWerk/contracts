// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CompensationModule_Integration_Test } from "test/integration/CompensationModule.t.sol";
import { Errors } from "src/modules/compensation-module/libraries/Errors.sol";
import { ICompensationModule } from "src/modules/compensation-module/interfaces/ICompensationModule.sol";

contract RefundComponent_Integration_Concrete_Test is CompensationModule_Integration_Test {
    function setUp() public override {
        CompensationModule_Integration_Test.setUp();

        // Make Eve the caller by default in all test suites as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });
    }

    function test_RevertWhen_ComponentNull() public {
        // Expect the call to revert with the {ComponentNull} error
        vm.expectRevert(Errors.ComponentNull.selector);

        // Run the test
        compensationModule.refundComponent({ componentId: 1 });
    }

    function test_RevertWhen_OnlyComponentSender() public whenComponentNotNull {
        // Expect the call to revert with the {OnlyComponentSender} error
        vm.expectRevert(Errors.OnlyComponentSender.selector);

        // Run the test
        compensationModule.refundComponent({ componentId: 1 });
    }

    function test_RefundComponent()
        public
        whenComponentNotNull
        whenComponentFunded
        whenCallerComponentSender(users.eve)
    {
        // Retrieve the refundable amount before the cancellation
        uint128 refundableAmount = compensationModule.refundableAmountOf({ streamId: 1 });

        // Sanity check: there should be a non-zero refundable amount
        assertGt(refundableAmount, 0);

        // Cache the balance of the {Space} contract before the refund
        uint256 balanceOfSpaceBefore = usdt.balanceOf(address(space));

        // Create the calldata for the `refundComponent` call
        bytes memory data = abi.encodeWithSelector(compensationModule.refundComponent.selector, 1);

        // Expect the {ComponentRefunded} event to be emitted
        vm.expectEmit();
        emit ICompensationModule.ComponentRefunded({ componentId: 1, refundedAmount: refundableAmount });

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Cache the balance of the {Space} contract after the refund
        uint256 balanceOfSpaceAfter = usdt.balanceOf(address(space));

        // Assert the entire refundable amount has been refunded to the sender's address (the Space)
        assertEq(balanceOfSpaceAfter - balanceOfSpaceBefore, refundableAmount);
    }
}
