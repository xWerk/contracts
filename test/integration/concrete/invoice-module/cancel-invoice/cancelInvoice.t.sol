// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CancelInvoice_Integration_Shared_Test } from "../../../shared/cancelInvoice.t.sol";
import { Types } from "./../../../../../src/modules/invoice-module/libraries/Types.sol";
import { Events } from "../../../../utils/Events.sol";
import { Errors } from "../../../../utils/Errors.sol";

contract CancelInvoice_Integration_Concret_Test is CancelInvoice_Integration_Shared_Test {
    function setUp() public virtual override {
        CancelInvoice_Integration_Shared_Test.setUp();
    }

    function test_RevertWhen_InvoiceIsPaid() external {
        // Set the one-off ETH transfer invoice as current one
        uint256 invoiceId = 2;

        // Make Bob the payer for the default invoice
        vm.startPrank({ msgSender: users.bob });

        // Pay the invoice first
        invoiceModule.payInvoice{ value: invoices[invoiceId].payment.amount }({ id: invoiceId });

        // Make Eve the caller who is the recipient of the invoice
        vm.startPrank({ msgSender: users.eve });

        // Expect the call to revert with the {CannotCancelPaidInvoice} error
        vm.expectRevert(Errors.CannotCancelPaidInvoice.selector);

        // Run the test
        invoiceModule.cancelInvoice({ id: invoiceId });
    }

    function test_RevertWhen_InvoiceIsCanceled() external whenInvoiceNotAlreadyPaid {
        // Set the one-off ETH transfer invoice as current one
        uint256 invoiceId = 2;

        // Make Eve's space the caller which is the recipient of the invoice
        vm.startPrank({ msgSender: address(space) });

        // Cancel the invoice first
        invoiceModule.cancelInvoice({ id: invoiceId });

        // Expect the call to revert with the {InvoiceAlreadyCanceled} error
        vm.expectRevert(Errors.InvoiceAlreadyCanceled.selector);

        // Run the test
        invoiceModule.cancelInvoice({ id: invoiceId });
    }

    function test_RevertWhen_PaymentMethodTransfer_SenderNotInvoiceRecipient()
        external
        whenInvoiceNotAlreadyPaid
        whenInvoiceNotCanceled
        givenPaymentMethodTransfer
    {
        // Set the one-off ETH transfer invoice as current one
        uint256 invoiceId = 2;

        // Make Bob the caller who IS NOT the recipient of the invoice
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to revert with the {OnlyInvoiceRecipient} error
        vm.expectRevert(Errors.OnlyInvoiceRecipient.selector);

        // Run the test
        invoiceModule.cancelInvoice({ id: invoiceId });
    }

    function test_CancelInvoice_PaymentMethodTransfer()
        external
        whenInvoiceNotAlreadyPaid
        whenInvoiceNotCanceled
        givenPaymentMethodTransfer
        whenSenderInvoiceRecipient
    {
        // Set the one-off ETH transfer invoice as current one
        uint256 invoiceId = 2;

        // Make Eve's space the caller which is the recipient of the invoice
        vm.startPrank({ msgSender: address(space) });

        // Expect the {InvoiceCanceled} event to be emitted
        vm.expectEmit();
        emit Events.InvoiceCanceled({ id: invoiceId });

        // Run the test
        invoiceModule.cancelInvoice({ id: invoiceId });

        // Assert the actual and expected invoice status
        Types.Invoice memory invoice = invoiceModule.getInvoice({ id: invoiceId });
        assertEq(uint8(invoice.status), uint8(Types.Status.Canceled));
    }

    function test_RevertWhen_PaymentMethodLinearStream_StatusPending_SenderNotInvoiceRecipient()
        external
        whenInvoiceNotAlreadyPaid
        whenInvoiceNotCanceled
        givenPaymentMethodLinearStream
        givenInvoiceStatusPending
    {
        // Set current invoice as a linear stream-based one
        uint256 invoiceId = 5;

        // Make Bob the caller who IS NOT the recipient of the invoice
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to revert with the {OnlyInvoiceRecipient} error
        vm.expectRevert(Errors.OnlyInvoiceRecipient.selector);

        // Run the test
        invoiceModule.cancelInvoice({ id: invoiceId });
    }

    function test_CancelInvoice_PaymentMethodLinearStream_StatusPending()
        external
        whenInvoiceNotAlreadyPaid
        whenInvoiceNotCanceled
        givenPaymentMethodLinearStream
        givenInvoiceStatusPending
        whenSenderInvoiceRecipient
    {
        // Set current invoice as a linear stream-based one
        uint256 invoiceId = 5;

        // Make Eve's space the caller which is the recipient of the invoice
        vm.startPrank({ msgSender: address(space) });

        // Expect the {InvoiceCanceled} event to be emitted
        vm.expectEmit();
        emit Events.InvoiceCanceled({ id: invoiceId });

        // Run the test
        invoiceModule.cancelInvoice({ id: invoiceId });

        // Assert the actual and expected invoice status
        Types.Invoice memory invoice = invoiceModule.getInvoice({ id: invoiceId });
        assertEq(uint8(invoice.status), uint8(Types.Status.Canceled));
    }

    function test_RevertWhen_PaymentMethodLinearStream_StatusOngoing_SenderNoInitialtStreamSender()
        external
        whenInvoiceNotAlreadyPaid
        whenInvoiceNotCanceled
        givenPaymentMethodLinearStream
        givenInvoiceStatusOngoing
    {
        // Set current invoice as a linear stream-based one
        uint256 invoiceId = 5;

        // The invoice must be paid for its status to be updated to `Ongoing`
        // Make Bob the payer of the invoice (also Bob will be the stream sender)
        vm.startPrank({ msgSender: users.bob });

        // Approve the {InvoiceModule} to transfer the USDT tokens on Bob's behalf
        usdt.approve({ spender: address(invoiceModule), amount: invoices[invoiceId].payment.amount });

        // Pay the invoice first (status will be updated to `Ongoing`)
        invoiceModule.payInvoice{ value: invoices[invoiceId].payment.amount }({ id: invoiceId });

        // Make Eve the caller who IS NOT the initial stream sender but rather the recipient
        vm.startPrank({ msgSender: users.eve });

        // Expect the call to revert with the {OnlyInitialStreamSender} error
        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyInitialStreamSender.selector, users.bob));

        // Run the test
        invoiceModule.cancelInvoice({ id: invoiceId });
    }

    function test_CancelInvoice_PaymentMethodLinearStream_StatusOngoing()
        external
        whenInvoiceNotAlreadyPaid
        whenInvoiceNotCanceled
        givenPaymentMethodLinearStream
        givenInvoiceStatusOngoing
        whenSenderInitialStreamSender
    {
        // Set current invoice as a linear stream-based one
        uint256 invoiceId = 5;

        // The invoice must be paid for its status to be updated to `Ongoing`
        // Make Bob the payer of the invoice (also Bob will be the initial stream sender)
        vm.startPrank({ msgSender: users.bob });

        // Approve the {InvoiceModule} to transfer the USDT tokens on Bob's behalf
        usdt.approve({ spender: address(invoiceModule), amount: invoices[invoiceId].payment.amount });

        // Pay the invoice first (status will be updated to `Ongoing`)
        invoiceModule.payInvoice{ value: invoices[invoiceId].payment.amount }({ id: invoiceId });

        // Expect the {InvoiceCanceled} event to be emitted
        vm.expectEmit();
        emit Events.InvoiceCanceled({ id: invoiceId });

        // Run the test
        invoiceModule.cancelInvoice({ id: invoiceId });

        // Assert the actual and expected invoice status
        Types.Invoice memory invoice = invoiceModule.getInvoice({ id: invoiceId });
        assertEq(uint8(invoice.status), uint8(Types.Status.Canceled));
    }

    function test_RevertWhen_PaymentMethodTranchedStream_StatusPending_SenderNotInvoiceRecipient()
        external
        whenInvoiceNotAlreadyPaid
        whenInvoiceNotCanceled
        givenPaymentMethodTranchedStream
        givenInvoiceStatusPending
    {
        // Set current invoice as a tranched stream-based one
        uint256 invoiceId = 5;

        // Make Bob the caller who IS NOT the recipient of the invoice
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to revert with the {OnlyInvoiceRecipient} error
        vm.expectRevert(Errors.OnlyInvoiceRecipient.selector);

        // Run the test
        invoiceModule.cancelInvoice({ id: invoiceId });
    }

    function test_CancelInvoice_PaymentMethodTranchedStream_StatusPending()
        external
        whenInvoiceNotAlreadyPaid
        whenInvoiceNotCanceled
        givenPaymentMethodTranchedStream
        givenInvoiceStatusPending
        whenSenderInvoiceRecipient
    {
        // Set current invoice as a tranched stream-based one
        uint256 invoiceId = 5;

        // Make Eve's space the caller which is the recipient of the invoice
        vm.startPrank({ msgSender: address(space) });

        // Expect the {InvoiceCanceled} event to be emitted
        vm.expectEmit();
        emit Events.InvoiceCanceled({ id: invoiceId });

        // Run the test
        invoiceModule.cancelInvoice({ id: invoiceId });

        // Assert the actual and expected invoice status
        Types.Invoice memory invoice = invoiceModule.getInvoice({ id: invoiceId });
        assertEq(uint8(invoice.status), uint8(Types.Status.Canceled));
    }

    function test_RevertWhen_PaymentMethodTranchedStream_StatusOngoing_SenderNoInitialtStreamSender()
        external
        whenInvoiceNotAlreadyPaid
        whenInvoiceNotCanceled
        givenPaymentMethodTranchedStream
        givenInvoiceStatusOngoing
    {
        // Set current invoice as a tranched stream-based one
        uint256 invoiceId = 5;

        // The invoice must be paid for its status to be updated to `Ongoing`
        // Make Bob the payer of the invoice (also Bob will be the stream sender)
        vm.startPrank({ msgSender: users.bob });

        // Approve the {InvoiceModule} to transfer the USDT tokens on Bob's behalf
        usdt.approve({ spender: address(invoiceModule), amount: invoices[invoiceId].payment.amount });

        // Pay the invoice first (status will be updated to `Ongoing`)
        invoiceModule.payInvoice{ value: invoices[invoiceId].payment.amount }({ id: invoiceId });

        // Make Eve the caller who IS NOT the initial stream sender but rather the recipient
        vm.startPrank({ msgSender: users.eve });

        // Expect the call to revert with the {OnlyInitialStreamSender} error
        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyInitialStreamSender.selector, users.bob));

        // Run the test
        invoiceModule.cancelInvoice({ id: invoiceId });
    }

    function test_CancelInvoice_PaymentMethodTranchedStream_StatusOngoing()
        external
        whenInvoiceNotAlreadyPaid
        whenInvoiceNotCanceled
        givenPaymentMethodTranchedStream
        givenInvoiceStatusOngoing
        whenSenderInitialStreamSender
    {
        // Set current invoice as a tranched stream-based one
        uint256 invoiceId = 5;

        // The invoice must be paid for its status to be updated to `Ongoing`
        // Make Bob the payer of the invoice (also Bob will be the initial stream sender)
        vm.startPrank({ msgSender: users.bob });

        // Approve the {InvoiceModule} to transfer the USDT tokens on Bob's behalf
        usdt.approve({ spender: address(invoiceModule), amount: invoices[invoiceId].payment.amount });

        // Pay the invoice first (status will be updated to `Ongoing`)
        invoiceModule.payInvoice{ value: invoices[invoiceId].payment.amount }({ id: invoiceId });

        // Expect the {InvoiceCanceled} event to be emitted
        vm.expectEmit();
        emit Events.InvoiceCanceled({ id: invoiceId });

        // Run the test
        invoiceModule.cancelInvoice({ id: invoiceId });

        // Assert the actual and expected invoice status
        Types.Invoice memory invoice = invoiceModule.getInvoice({ id: invoiceId });
        assertEq(uint8(invoice.status), uint8(Types.Status.Canceled));
    }
}
