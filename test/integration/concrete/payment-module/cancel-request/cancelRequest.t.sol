// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CancelRequest_Integration_Shared_Test } from "../../../shared/cancelRequest.t.sol";
import { Types } from "./../../../../../src/modules/payment-module/libraries/Types.sol";
import { Events } from "../../../../utils/Events.sol";
import { Errors } from "../../../../utils/Errors.sol";

contract CancelRequest_Integration_Concret_Test is CancelRequest_Integration_Shared_Test {
    function setUp() public virtual override {
        CancelRequest_Integration_Shared_Test.setUp();
    }

    function test_RevertWhen_InvoiceIsPaid() external {
        // Set the one-off ETH transfer payment request as current one
        uint256 paymentRequestId = 2;

        // Make Bob the payer for the default paymentRequest
        vm.startPrank({ msgSender: users.bob });

        // Pay the payment request first
        paymentModule.payRequest{ value: paymentRequests[paymentRequestId].config.amount }({
            requestId: paymentRequestId
        });

        // Make Eve the caller who is the recipient of the payment request
        vm.startPrank({ msgSender: users.eve });

        // Expect the call to revert with the {RequestPaid} error
        vm.expectRevert(Errors.RequestPaid.selector);

        // Run the test
        paymentModule.cancelRequest({ requestId: paymentRequestId });
    }

    function test_RevertWhen_RequestCanceled() external whenRequestNotAlreadyPaid {
        // Set the one-off ETH transfer payment request as current one
        uint256 paymentRequestId = 2;

        // Make Eve's space the caller which is the recipient of the payment request
        vm.startPrank({ msgSender: address(space) });

        // Cancel the payment request first
        paymentModule.cancelRequest({ requestId: paymentRequestId });

        // Expect the call to revert with the {RequestCanceled} error
        vm.expectRevert(Errors.RequestCanceled.selector);

        // Run the test
        paymentModule.cancelRequest({ requestId: paymentRequestId });
    }

    function test_RevertWhen_PaymentMethodTransfer_SenderNotInvoiceRecipient()
        external
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodTransfer
    {
        // Set the one-off ETH transfer payment request as current one
        uint256 paymentRequestId = 2;

        // Make Bob the caller who IS NOT the recipient of the payment request
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to revert with the {OnlyRequestRecipient} error
        vm.expectRevert(Errors.OnlyRequestRecipient.selector);

        // Run the test
        paymentModule.cancelRequest({ requestId: paymentRequestId });
    }

    function test_CancelRequest_PaymentMethodTransfer()
        external
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodTransfer
        whenSenderInvoiceRecipient
    {
        // Set the one-off ETH transfer payment request as current one
        uint256 paymentRequestId = 2;

        // Make Eve's space the caller which is the recipient of the payment request
        vm.startPrank({ msgSender: address(space) });

        // Expect the {RequestCanceled} event to be emitted
        vm.expectEmit();
        emit Events.RequestCanceled({ requestId: paymentRequestId });

        // Run the test
        paymentModule.cancelRequest({ requestId: paymentRequestId });

        // Assert the actual and expected paymentRequest status
        Types.Status paymentRequestStatus = paymentModule.statusOf({ requestId: paymentRequestId });
        assertEq(uint8(paymentRequestStatus), uint8(Types.Status.Canceled));
    }

    function test_RevertWhen_PaymentMethodLinearStream_StatusPending_SenderNotInvoiceRecipient()
        external
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodLinearStream
        givenInvoiceStatusPending
    {
        // Set current paymentRequest as a linear stream-based one
        uint256 paymentRequestId = 5;

        // Make Bob the caller who IS NOT the recipient of the payment request
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to revert with the {OnlyRequestRecipient} error
        vm.expectRevert(Errors.OnlyRequestRecipient.selector);

        // Run the test
        paymentModule.cancelRequest({ requestId: paymentRequestId });
    }

    function test_CancelRequest_PaymentMethodLinearStream_StatusCanceled()
        external
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodLinearStream
        givenInvoiceStatusPending
        whenSenderInvoiceRecipient
    {
        // Set current paymentRequest as a linear stream-based one
        uint256 paymentRequestId = 5;

        // Make Eve's space the caller which is the recipient of the payment request
        vm.startPrank({ msgSender: address(space) });

        // Expect the {RequestCanceled} event to be emitted
        vm.expectEmit();
        emit Events.RequestCanceled({ requestId: paymentRequestId });

        // Run the test
        paymentModule.cancelRequest({ requestId: paymentRequestId });

        // Assert the actual and expected paymentRequest status
        Types.Status paymentRequestStatus = paymentModule.statusOf({ requestId: paymentRequestId });
        assertEq(uint8(paymentRequestStatus), uint8(Types.Status.Canceled));
    }

    function test_RevertWhen_PaymentMethodLinearStream_StatusPending_SenderNoInitialtStreamSender()
        external
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodLinearStream
        givenRequestStatusPending
    {
        // Set current paymentRequest as a linear stream-based one
        uint256 paymentRequestId = 5;

        // The payment request must be paid for its status to be updated to `Accepted`
        // Make Bob the payer of the payment request (also Bob will be the stream sender)
        vm.startPrank({ msgSender: users.bob });

        // Approve the {InvoiceModule} to transfer the USDT tokens on Bob's behalf
        usdt.approve({ spender: address(paymentModule), amount: paymentRequests[paymentRequestId].config.amount });

        // Pay the payment request first (status will be updated to `Accepted`)
        paymentModule.payRequest{ value: paymentRequests[paymentRequestId].config.amount }({
            requestId: paymentRequestId
        });

        // Make Eve the caller who IS NOT the initial stream sender but rather the recipient
        vm.startPrank({ msgSender: users.eve });

        // Expect the call to revert with the {OnlyInitialStreamSender} error
        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyInitialStreamSender.selector, users.bob));

        // Run the test
        paymentModule.cancelRequest({ requestId: paymentRequestId });
    }

    function test_CancelRequest_PaymentMethodLinearStream_StatusPending()
        external
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodLinearStream
        givenRequestStatusPending
        whenSenderInitialStreamSender
    {
        // Set current paymentRequest as a linear stream-based one
        uint256 paymentRequestId = 5;

        // The payment request must be paid for its status to be updated to `Accepted`
        // Make Bob the payer of the payment request (also Bob will be the initial stream sender)
        vm.startPrank({ msgSender: users.bob });

        // Approve the {InvoiceModule} to transfer the USDT tokens on Bob's behalf
        usdt.approve({ spender: address(paymentModule), amount: paymentRequests[paymentRequestId].config.amount });

        // Pay the payment request first (status will be updated to `Accepted`)
        paymentModule.payRequest{ value: paymentRequests[paymentRequestId].config.amount }({
            requestId: paymentRequestId
        });

        // Expect the {RequestCanceled} event to be emitted
        vm.expectEmit();
        emit Events.RequestCanceled({ requestId: paymentRequestId });

        // Make Bob the caller who is the sender of the payment request stream
        vm.startPrank({ msgSender: users.bob });

        // Run the test
        paymentModule.cancelRequest({ requestId: paymentRequestId });

        // Assert the actual and expected paymentRequest status
        Types.Status paymentRequestStatus = paymentModule.statusOf({ requestId: paymentRequestId });
        assertEq(uint8(paymentRequestStatus), uint8(Types.Status.Canceled));
    }

    function test_RevertWhen_PaymentMethodTranchedStream_StatusPending_SenderNotInvoiceRecipient()
        external
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodTranchedStream
        givenInvoiceStatusPending
    {
        // Set current paymentRequest as a tranched stream-based one
        uint256 paymentRequestId = 5;

        // Make Bob the caller who IS NOT the recipient of the payment request
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to revert with the {OnlyRequestRecipient} error
        vm.expectRevert(Errors.OnlyRequestRecipient.selector);

        // Run the test
        paymentModule.cancelRequest({ requestId: paymentRequestId });
    }

    function test_CancelRequest_PaymentMethodTranchedStream_StatusCanceled()
        external
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodTranchedStream
        givenInvoiceStatusPending
        whenSenderInvoiceRecipient
    {
        // Set current paymentRequest as a tranched stream-based one
        uint256 paymentRequestId = 5;

        // Make Eve's space the caller which is the recipient of the payment request
        vm.startPrank({ msgSender: address(space) });

        // Expect the {RequestCanceled} event to be emitted
        vm.expectEmit();
        emit Events.RequestCanceled({ requestId: paymentRequestId });

        // Run the test
        paymentModule.cancelRequest({ requestId: paymentRequestId });

        // Assert the actual and expected paymentRequest status
        Types.Status paymentRequestStatus = paymentModule.statusOf({ requestId: paymentRequestId });
        assertEq(uint8(paymentRequestStatus), uint8(Types.Status.Canceled));
    }

    function test_RevertWhen_PaymentMethodTranchedStream_StatusPending_SenderNoInitialtStreamSender()
        external
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodTranchedStream
        givenRequestStatusPending
    {
        // Set current paymentRequest as a tranched stream-based one
        uint256 paymentRequestId = 5;

        // The payment request must be paid for its status to be updated to `Accepted`
        // Make Bob the payer of the payment request (also Bob will be the stream sender)
        vm.startPrank({ msgSender: users.bob });

        // Approve the {InvoiceModule} to transfer the USDT tokens on Bob's behalf
        usdt.approve({ spender: address(paymentModule), amount: paymentRequests[paymentRequestId].config.amount });

        // Pay the payment request first (status will be updated to `Accepted`)
        paymentModule.payRequest{ value: paymentRequests[paymentRequestId].config.amount }({
            requestId: paymentRequestId
        });

        // Make Eve the caller who IS NOT the initial stream sender but rather the recipient
        vm.startPrank({ msgSender: users.eve });

        // Expect the call to revert with the {OnlyInitialStreamSender} error
        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyInitialStreamSender.selector, users.bob));

        // Run the test
        paymentModule.cancelRequest({ requestId: paymentRequestId });
    }

    function test_CancelRequest_PaymentMethodTranchedStream_StatusPending()
        external
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodTranchedStream
        givenRequestStatusPending
        whenSenderInitialStreamSender
    {
        // Set current paymentRequest as a tranched stream-based one
        uint256 paymentRequestId = 5;

        // The payment request must be paid for its status to be updated to `Accepted`
        // Make Bob the payer of the payment request (also Bob will be the initial stream sender)
        vm.startPrank({ msgSender: users.bob });

        // Approve the {InvoiceModule} to transfer the USDT tokens on Bob's behalf
        usdt.approve({ spender: address(paymentModule), amount: paymentRequests[paymentRequestId].config.amount });

        // Pay the payment request first (status will be updated to `Accepted`)
        paymentModule.payRequest{ value: paymentRequests[paymentRequestId].config.amount }({
            requestId: paymentRequestId
        });

        // Expect the {RequestCanceled} event to be emitted
        vm.expectEmit();
        emit Events.RequestCanceled({ requestId: paymentRequestId });

        // Run the test
        paymentModule.cancelRequest({ requestId: paymentRequestId });

        // Assert the actual and expected paymentRequest status
        Types.Status paymentRequestStatus = paymentModule.statusOf({ requestId: paymentRequestId });
        assertEq(uint8(paymentRequestStatus), uint8(Types.Status.Canceled));
    }
}
