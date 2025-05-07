// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CompensationModule_Integration_Test } from "test/integration/CompensationModule.t.sol";
import { Errors } from "src/modules/compensation-module/libraries/Errors.sol";
import { Flow } from "@sablier/flow/src/types/DataTypes.sol";
import { ICompensationModule } from "src/modules/compensation-module/interfaces/ICompensationModule.sol";

contract WithdrawFromComponent_Integration_Concrete_Test is CompensationModule_Integration_Test {
    function setUp() public override {
        CompensationModule_Integration_Test.setUp();

        // Make Eve the caller by default in all test suites as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });
    }

    function test_RevertWhen_CompensationComponentNull() public {
        // Expect the call to revert with the {CompensationComponentNull} error
        vm.expectRevert(Errors.CompensationComponentNull.selector);

        // Run the test
        compensationModule.withdrawFromComponent(1, 0);
    }

    function test_RevertWhen_CallerIsNotCompensationPlanRecipient() public whenComponentNotNull {
        // Expect the call to revert with the {OnlyCompensationPlanRecipient} error
        vm.expectRevert(Errors.OnlyCompensationPlanRecipient.selector);

        // Run the test with Eve as the caller as she's not the compensation plan recipient (Bob is)
        compensationModule.withdrawFromComponent(1, 0);
    }

    function test_WithdrawFromComponent()
        public
        whenComponentNotNull
        whenComponentPartiallyFunded
        whenCallerCompensationPlanRecipient
    {
        // Fast forward the time by 1 day to ensure the stream amount is fully streamed
        vm.warp(block.timestamp + 1 days);

        // Cache the USDT balance of Bob before the withdrawal
        uint256 balanceOfBobBefore = usdt.balanceOf(users.bob);

        // Expect the {CompensationComponentWithdrawn} event to be emitted
        vm.expectEmit();
        emit ICompensationModule.CompensationComponentWithdrawn(1, 0, 10e6);

        // Run the test
        compensationModule.withdrawFromComponent(1, 0);

        // Cache the USDT balance of Bob after the withdrawal
        uint256 balanceOfBobAfter = usdt.balanceOf(users.bob);

        // Assert the USDT balance of Bob increased by the amount withdrawn
        assertEq(balanceOfBobAfter - balanceOfBobBefore, 10e6);

        // Assert the actual and expected status of the compensation component stream
        // The stream is now insolvent because the total debt exceeds the stream balance
        uint8 actualStatusOfComponent = uint8(compensationModule.statusOfComponent(1, 0));
        assertEq(actualStatusOfComponent, uint8(Flow.Status.STREAMING_INSOLVENT));
    }
}
