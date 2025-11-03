// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { WithdrawLinearStream_Integration_Shared_Test } from "../../../shared/withdrawLinearStream.t.sol";
import { Errors } from "src/modules/payment-module/libraries/Errors.sol";

contract WithdrawMaxRequestStream_Integration_Concret_Test is WithdrawLinearStream_Integration_Shared_Test {
    function setUp() public virtual override {
        WithdrawLinearStream_Integration_Shared_Test.setUp();
    }

    function test_RevertWhen_RequestIsNull() external {
        // Set current paymentRequest to a null one
        uint256 paymentRequestId = 999;

        // Expect the call to revert with the {NullRequest} error
        vm.expectRevert(Errors.NullRequest.selector);

        // Run the test
        paymentModule.withdrawMaxRequestStream(paymentRequestId);
    }

    function test_RevertWhen_PaymentMethodTransfer() external whenRequestNotNull {
        // Set current paymentRequest as a transfer-based one
        uint256 paymentRequestId = 2;

        // Expect the call to revert with the {OnlyForStreamPaymentMethods} error
        vm.expectRevert(Errors.OnlyForStreamPaymentMethods.selector);

        // Run the test
        paymentModule.withdrawMaxRequestStream(paymentRequestId);
    }

    function test_RevertWhen_CallerNotStreamRecipient()
        external
        whenRequestNotNull
        givenPaymentMethodLinearStream
        givenRequestStatusPending
    {
        // Set current paymentRequest as a linear stream-based one
        uint256 paymentRequestId = 4;

        // The payment request must be paid in order to update its status to `Ongoing`
        // Make Bob the payer of the payment request (also Bob will be the initial stream sender)
        vm.startPrank({ msgSender: users.bob });

        // Approve the {PaymentModule} to transfer the USDT tokens on Bob's behalf
        usdt.approve({ spender: address(paymentModule), amount: paymentRequests[paymentRequestId].config.amount });

        // Pay the payment request first (status will be updated to `Ongoing`)
        paymentModule.payRequest{ value: paymentRequests[paymentRequestId].config.amount }({
            requestId: paymentRequestId
        });

        // Advance the timestamp by 5 weeks to simulate the withdrawal
        vm.warp(block.timestamp + 5 weeks);

        // Make bob who is not the stream recipient the caller
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to revert with the {OnlyStreamRecipient} error
        vm.expectRevert(Errors.OnlyStreamRecipient.selector);

        // Run the test
        paymentModule.withdrawMaxRequestStream(paymentRequestId);
    }

    function test_WithdrawMaxStream_LinearStream() external givenPaymentMethodLinearStream givenRequestStatusPending {
        // Set current paymentRequest as a linear stream-based one
        uint256 paymentRequestId = 4;
        uint256 streamId = 1;

        // The payment request must be paid in order to update its status to `Ongoing`
        // Make Bob the payer of the payment request (also Bob will be the initial stream sender)
        vm.startPrank({ msgSender: users.bob });

        // Approve the {PaymentModule} to transfer the USDT tokens on Bob's behalf
        usdt.approve({ spender: address(paymentModule), amount: paymentRequests[paymentRequestId].config.amount });

        // Pay the payment request first (status will be updated to `Ongoing`)
        paymentModule.payRequest{ value: paymentRequests[paymentRequestId].config.amount }({
            requestId: paymentRequestId
        });

        // Advance the timestamp by 5 weeks to simulate the withdrawal
        vm.warp(block.timestamp + 5 weeks);

        // Store Eve's space balance before withdrawing the USDT tokens
        uint256 balanceOfBefore = usdt.balanceOf(address(space));

        // Get the maximum withdrawable amount from the stream
        uint128 maxWithdrawableAmount = paymentModule.withdrawableAmountOf({ streamId: streamId });

        // Make Eve's space the caller in this test suite as her space is the recipient of the payment request
        vm.startPrank({ msgSender: address(space) });

        // Run the test
        paymentModule.withdrawMaxRequestStream(paymentRequestId);

        // Assert the current and expected USDT balance of Eve
        assertEq(balanceOfBefore + maxWithdrawableAmount, usdt.balanceOf(address(space)));
    }

    function test_WithdrawMaxStream_TranchedStream()
        external
        givenPaymentMethodTranchedStream
        givenRequestStatusPending
    {
        // Set current paymentRequest as a tranched stream-based one
        uint256 paymentRequestId = 5;
        uint256 streamId = 1;

        // The payment request must be paid for its status to be updated to `Ongoing`
        // Make Bob the payer of the payment request (also Bob will be the initial stream sender)
        vm.startPrank({ msgSender: users.bob });

        // Approve the {PaymentModule} to transfer the USDT tokens on Bob's behalf
        usdt.approve({ spender: address(paymentModule), amount: paymentRequests[paymentRequestId].config.amount });

        // Pay the payment request first (status will be updated to `Ongoing`)
        paymentModule.payRequest{ value: paymentRequests[paymentRequestId].config.amount }({
            requestId: paymentRequestId
        });

        // Advance the timestamp by 5 weeks to simulate the withdrawal
        vm.warp(block.timestamp + 5 weeks);

        // Store Eve's space balance before withdrawing the USDT tokens
        uint256 balanceOfBefore = usdt.balanceOf(address(space));

        // Get the maximum withdrawable amount from the stream
        uint128 maxWithdrawableAmount = paymentModule.withdrawableAmountOf({ streamId: streamId });

        // Make Eve's space the caller in this test suite as her space is the owner of the payment request
        vm.startPrank({ msgSender: address(space) });

        // Run the test
        paymentModule.withdrawMaxRequestStream(paymentRequestId);

        // Assert the current and expected USDT balance of Eve's space
        assertEq(balanceOfBefore + maxWithdrawableAmount, usdt.balanceOf(address(space)));
    }
}
