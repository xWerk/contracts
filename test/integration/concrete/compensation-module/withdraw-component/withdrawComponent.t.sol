// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CompensationModule_Integration_Test } from "test/integration/CompensationModule.t.sol";
import { Errors } from "src/modules/compensation-module/libraries/Errors.sol";
import { ICompensationModule } from "src/modules/compensation-module/interfaces/ICompensationModule.sol";

contract WithdrawComponent_Integration_Concrete_Test is CompensationModule_Integration_Test {
    function setUp() public override {
        CompensationModule_Integration_Test.setUp();

        // Make Eve the caller by default in all test suites as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });
    }

    function test_RevertWhen_ComponentNull() public {
        // Expect the call to revert with the {ComponentNull} error
        vm.expectRevert(Errors.ComponentNull.selector);

        // Run the test
        compensationModule.withdrawComponent({ componentId: 1, amount: 4e6 });
    }

    function test_RevertWhen_CallerIsNotComponentRecipient() public whenComponentNotNull {
        // Expect the call to revert with the {OnlyComponentRecipient} error
        vm.expectRevert(Errors.OnlyComponentRecipient.selector);

        // Run the test with Eve as the caller as she's not the compensation component recipient (Bob is)
        compensationModule.withdrawComponent({ componentId: 1, amount: 4e6 });
    }

    function test_RevertWhen_MsgValueNotEnough() public whenComponentNotNull whenCallerComponentRecipient(users.bob) {
        // Retrieve the minimum fee required to withdraw
        uint256 minFee = compensationModule.calculateMinFeeWei({ streamId: 1 });

        // Compute an insufficient fee amount to simulate the error
        uint256 actualFee = minFee / 2;

        // Expect the call to revert with the {InsufficientFee} error
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientFee.selector, actualFee, minFee));

        // Run the test with insufficient `msg.value`
        compensationModule.withdrawComponent{ value: actualFee }({ componentId: 1, amount: 0 });
    }

    function test_RevertWhen_AmountIsZero()
        public
        whenComponentNotNull
        whenCallerComponentRecipient(users.bob)
        whenEnoughMsgValue
    {
        // Retrieve the minimum fee required to withdraw
        uint256 minFee = compensationModule.calculateMinFeeWei({ streamId: 1 });

        // Expect the call to revert with the {InvalidZeroWithdrawAmount} error
        vm.expectRevert(Errors.InvalidZeroWithdrawAmount.selector);

        // Run the test with Eve as the caller as she's not the compensation component recipient (Bob is)
        compensationModule.withdrawComponent{ value: minFee }({ componentId: 1, amount: 0 });
    }

    function test_RevertWhen_AmountExceedsWithdrawableAmount()
        public
        whenComponentNotNull
        whenComponentPartiallyFunded
        whenCallerComponentRecipient(users.bob)
        whenAmountNotZero
        whenEnoughMsgValue
    {
        // Retrieve the minimum fee required to withdraw
        uint256 minFee = compensationModule.calculateMinFeeWei({ streamId: 1 });

        // Retrieve the withdrawable amount
        uint128 withdrawableAmount = compensationModule.withdrawableAmountOfComponent({ componentId: 1 });

        // Expect the call to revert with the {Overdraw} error
        vm.expectRevert(Errors.Overdraw.selector);

        // Run the test with amount slightly greater than the withdrawable amount
        compensationModule.withdrawComponent{ value: minFee }({ componentId: 1, amount: withdrawableAmount + 1 });
    }

    function test_WithdrawComponent()
        public
        whenComponentNotNull
        whenComponentPartiallyFunded
        whenCallerComponentRecipient(users.bob)
        whenAmountNotZero
        whenAmountDoesNotExceedWithdrawableAmount
        whenEnoughMsgValue
    {
        // Retrieve the minimum fee required to withdraw
        uint256 minFee = compensationModule.calculateMinFeeWei({ streamId: 1 });

        // Cache the USDT balance of Bob before the withdrawal
        uint256 balanceOfBobBefore = usdt.balanceOf(users.bob);

        // Expect the {ComponentWithdrawn} event to be emitted
        vm.expectEmit();
        emit ICompensationModule.ComponentWithdrawn({ componentId: 1, amount: 4e6, feePaid: minFee });

        // Run the test
        compensationModule.withdrawComponent{ value: minFee }({ componentId: 1, amount: 4e6 });

        // Cache the USDT balance of Bob after the withdrawal
        uint256 balanceOfBobAfter = usdt.balanceOf(users.bob);

        // Assert the USDT balance of Bob increased by the amount withdrawn
        assertEq(balanceOfBobAfter - balanceOfBobBefore, 4e6);
    }
}
