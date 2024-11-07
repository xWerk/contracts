// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PayInvoice_Integration_Shared_Test } from "../../../shared/payInvoice.t.sol";
import { Types } from "./../../../../../src/modules/invoice-module/libraries/Types.sol";
import { Events } from "../../../../utils/Events.sol";
import { Errors } from "../../../../utils/Errors.sol";

import { LockupLinear, LockupTranched } from "@sablier/v2-core/src/types/DataTypes.sol";

contract PayInvoice_Integration_Concret_Test is PayInvoice_Integration_Shared_Test {
    function setUp() public virtual override {
        PayInvoice_Integration_Shared_Test.setUp();
    }

    function test_RevertWhen_InvoiceNull() external {
        // Expect the call to revert with the {ERC721NonexistentToken} error
        vm.expectRevert(abi.encodeWithSelector(Errors.ERC721NonexistentToken.selector, 99));

        // Run the test
        invoiceModule.payInvoice({ id: 99 });
    }

    function test_RevertWhen_InvoiceAlreadyPaid() external whenInvoiceNotNull {
        // Set the one-off USDT transfer invoice as current one
        uint256 invoiceId = 1;

        // Make Bob the payer for the default invoice
        vm.startPrank({ msgSender: users.bob });

        // Approve the {InvoiceModule} to transfer the ERC-20 token on Bob's behalf
        usdt.approve({ spender: address(invoiceModule), amount: invoices[invoiceId].payment.amount });

        // Pay first the invoice
        invoiceModule.payInvoice({ id: invoiceId });

        // Expect the call to be reverted with the {InvoiceAlreadyPaid} error
        vm.expectRevert(Errors.InvoiceAlreadyPaid.selector);

        // Run the test
        invoiceModule.payInvoice({ id: invoiceId });
    }

    function test_RevertWhen_InvoiceCanceled() external whenInvoiceNotNull whenInvoiceNotAlreadyPaid {
        // Set the one-off USDT transfer invoice as current one
        uint256 invoiceId = 1;

        // Make Eve's space the caller in this test suite as his space is the owner of the invoice
        vm.startPrank({ msgSender: address(space) });

        // Cancel the invoice first
        invoiceModule.cancelInvoice({ id: invoiceId });

        // Make Bob the payer of this invoice
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to be reverted with the {InvoiceCanceled} error
        vm.expectRevert(Errors.InvoiceCanceled.selector);

        // Run the test
        invoiceModule.payInvoice({ id: invoiceId });
    }

    function test_RevertWhen_PaymentMethodTransfer_PaymentAmountLessThanInvoiceValue()
        external
        whenInvoiceNotNull
        whenInvoiceNotAlreadyPaid
        whenInvoiceNotCanceled
        givenPaymentMethodTransfer
        givenPaymentAmountInNativeToken
    {
        // Set the one-off ETH transfer invoice as current one
        uint256 invoiceId = 2;

        // Make Bob the payer for the default invoice
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to be reverted with the {PaymentAmountLessThanInvoiceValue} error
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.PaymentAmountLessThanInvoiceValue.selector,
                invoices[invoiceId].payment.amount
            )
        );

        // Run the test
        invoiceModule.payInvoice{ value: invoices[invoiceId].payment.amount - 1 }({ id: invoiceId });
    }

    function test_RevertWhen_PaymentMethodTransfer_NativeTokenTransferFails()
        external
        whenInvoiceNotNull
        whenInvoiceNotAlreadyPaid
        whenInvoiceNotCanceled
        givenPaymentMethodTransfer
        givenPaymentAmountInNativeToken
        whenPaymentAmountEqualToInvoiceValue
    {
        // Create a mock invoice with a one-off ETH transfer from the Eve's space
        Types.Invoice memory invoice = createInvoiceWithOneOffTransfer({ asset: address(0) });
        executeCreateInvoice({ invoice: invoice, user: users.eve });

        uint256 invoiceId = _nextInvoiceId;

        // Make Eve's space the caller for the next call to approve & transfer the invoice NFT to a bad receiver
        vm.startPrank({ msgSender: address(space) });

        // Approve the {InvoiceModule} to transfer the token
        invoiceModule.approve({ to: address(invoiceModule), tokenId: invoiceId });

        // Transfer the invoice to a bad receiver so we can test against `NativeTokenPaymentFailed`
        invoiceModule.transferFrom({ from: address(space), to: address(mockBadReceiver), tokenId: invoiceId });

        // Make Bob the payer for this invoice
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to be reverted with the {NativeTokenPaymentFailed} error
        vm.expectRevert(Errors.NativeTokenPaymentFailed.selector);

        // Run the test
        invoiceModule.payInvoice{ value: invoice.payment.amount }({ id: invoiceId });
    }

    function test_PayInvoice_PaymentMethodTransfer_NativeToken_OneOff()
        external
        whenInvoiceNotNull
        whenInvoiceNotAlreadyPaid
        whenInvoiceNotCanceled
        givenPaymentMethodTransfer
        givenPaymentAmountInNativeToken
        whenPaymentAmountEqualToInvoiceValue
        whenNativeTokenPaymentSucceeds
    {
        // Set the one-off ETH transfer invoice as current one
        uint256 invoiceId = 2;

        // Make Bob the payer for the default invoice
        vm.startPrank({ msgSender: users.bob });

        // Store the ETH balances of Bob and recipient before paying the invoice
        uint256 balanceOfBobBefore = address(users.bob).balance;
        uint256 balanceOfRecipientBefore = address(space).balance;

        // Expect the {InvoicePaid} event to be emitted
        vm.expectEmit();
        emit Events.InvoicePaid({
            id: invoiceId,
            payer: users.bob,
            status: Types.Status.Paid,
            payment: Types.Payment({
                method: invoices[invoiceId].payment.method,
                recurrence: invoices[invoiceId].payment.recurrence,
                paymentsLeft: 0,
                asset: invoices[invoiceId].payment.asset,
                amount: invoices[invoiceId].payment.amount,
                streamId: 0
            })
        });

        // Run the test
        invoiceModule.payInvoice{ value: invoices[invoiceId].payment.amount }({ id: invoiceId });

        // Assert the actual and the expected state of the invoice
        Types.Invoice memory invoice = invoiceModule.getInvoice({ id: invoiceId });
        assertEq(uint8(invoice.status), uint8(Types.Status.Paid));
        assertEq(invoice.payment.paymentsLeft, 0);

        // Assert the balances of payer and recipient
        assertEq(address(users.bob).balance, balanceOfBobBefore - invoices[invoiceId].payment.amount);
        assertEq(address(space).balance, balanceOfRecipientBefore + invoices[invoiceId].payment.amount);
    }

    function test_PayInvoice_PaymentMethodTransfer_ERC20Token_Recurring()
        external
        whenInvoiceNotNull
        whenInvoiceNotAlreadyPaid
        whenInvoiceNotCanceled
        givenPaymentMethodTransfer
        givenPaymentAmountInERC20Tokens
        whenPaymentAmountEqualToInvoiceValue
    {
        // Set the recurring USDT transfer invoice as current one
        uint256 invoiceId = 3;

        // Make Bob the payer for the default invoice
        vm.startPrank({ msgSender: users.bob });

        // Store the USDT balances of Bob and recipient before paying the invoice
        uint256 balanceOfBobBefore = usdt.balanceOf(users.bob);
        uint256 balanceOfRecipientBefore = usdt.balanceOf(address(space));

        // Approve the {InvoiceModule} to transfer the ERC-20 tokens on Bob's behalf
        usdt.approve({ spender: address(invoiceModule), amount: invoices[invoiceId].payment.amount });

        // Expect the {InvoicePaid} event to be emitted
        vm.expectEmit();
        emit Events.InvoicePaid({
            id: invoiceId,
            payer: users.bob,
            status: Types.Status.Ongoing,
            payment: Types.Payment({
                method: invoices[invoiceId].payment.method,
                recurrence: invoices[invoiceId].payment.recurrence,
                paymentsLeft: 3,
                asset: invoices[invoiceId].payment.asset,
                amount: invoices[invoiceId].payment.amount,
                streamId: 0
            })
        });

        // Run the test
        invoiceModule.payInvoice{ value: invoices[invoiceId].payment.amount }({ id: invoiceId });

        // Assert the actual and the expected state of the invoice
        Types.Invoice memory invoice = invoiceModule.getInvoice({ id: invoiceId });
        assertEq(uint8(invoice.status), uint8(Types.Status.Ongoing));
        assertEq(invoice.payment.paymentsLeft, 3);

        // Assert the balances of payer and recipient
        assertEq(usdt.balanceOf(users.bob), balanceOfBobBefore - invoices[invoiceId].payment.amount);
        assertEq(usdt.balanceOf(address(space)), balanceOfRecipientBefore + invoices[invoiceId].payment.amount);
    }

    function test_PayInvoice_PaymentMethodLinearStream()
        external
        whenInvoiceNotNull
        whenInvoiceNotAlreadyPaid
        whenInvoiceNotCanceled
        givenPaymentMethodLinearStream
        givenPaymentAmountInERC20Tokens
        whenPaymentAmountEqualToInvoiceValue
    {
        // Set the linear USDT stream-based invoice as current one
        uint256 invoiceId = 4;

        // Make Bob the payer for the default invoice
        vm.startPrank({ msgSender: users.bob });

        // Approve the {InvoiceModule} to transfer the ERC-20 tokens on Bob's behalf
        usdt.approve({ spender: address(invoiceModule), amount: invoices[invoiceId].payment.amount });

        // Expect the {InvoicePaid} event to be emitted
        vm.expectEmit();
        emit Events.InvoicePaid({
            id: invoiceId,
            payer: users.bob,
            status: Types.Status.Ongoing,
            payment: Types.Payment({
                method: invoices[invoiceId].payment.method,
                recurrence: invoices[invoiceId].payment.recurrence,
                paymentsLeft: 0,
                asset: invoices[invoiceId].payment.asset,
                amount: invoices[invoiceId].payment.amount,
                streamId: 1
            })
        });

        // Run the test
        invoiceModule.payInvoice{ value: invoices[invoiceId].payment.amount }({ id: invoiceId });

        // Assert the actual and the expected state of the invoice
        Types.Invoice memory invoice = invoiceModule.getInvoice({ id: invoiceId });
        assertEq(uint8(invoice.status), uint8(Types.Status.Ongoing));
        assertEq(invoice.payment.streamId, 1);
        assertEq(invoice.payment.paymentsLeft, 0);

        // Assert the actual and the expected state of the Sablier v2 linear stream
        LockupLinear.StreamLL memory stream = invoiceModule.getLinearStream({ streamId: 1 });
        assertEq(stream.sender, address(invoiceModule));
        assertEq(stream.recipient, address(space));
        assertEq(address(stream.asset), address(usdt));
        assertEq(stream.startTime, invoice.startTime);
        assertEq(stream.endTime, invoice.endTime);
    }

    function test_PayInvoice_PaymentMethodTranchedStream()
        external
        whenInvoiceNotNull
        whenInvoiceNotAlreadyPaid
        whenInvoiceNotCanceled
        givenPaymentMethodTranchedStream
        givenPaymentAmountInERC20Tokens
        whenPaymentAmountEqualToInvoiceValue
    {
        // Set the tranched USDT stream-based invoice as current one
        uint256 invoiceId = 5;

        // Make Bob the payer for the default invoice
        vm.startPrank({ msgSender: users.bob });

        // Approve the {InvoiceModule} to transfer the ERC-20 tokens on Bob's behalf
        usdt.approve({ spender: address(invoiceModule), amount: invoices[invoiceId].payment.amount });

        // Expect the {InvoicePaid} event to be emitted
        vm.expectEmit();
        emit Events.InvoicePaid({
            id: invoiceId,
            payer: users.bob,
            status: Types.Status.Ongoing,
            payment: Types.Payment({
                method: invoices[invoiceId].payment.method,
                recurrence: invoices[invoiceId].payment.recurrence,
                paymentsLeft: 0,
                asset: invoices[invoiceId].payment.asset,
                amount: invoices[invoiceId].payment.amount,
                streamId: 1
            })
        });

        // Run the test
        invoiceModule.payInvoice{ value: invoices[invoiceId].payment.amount }({ id: invoiceId });

        // Assert the actual and the expected state of the invoice
        Types.Invoice memory invoice = invoiceModule.getInvoice({ id: invoiceId });
        assertEq(uint8(invoice.status), uint8(Types.Status.Ongoing));
        assertEq(invoice.payment.streamId, 1);
        assertEq(invoice.payment.paymentsLeft, 0);

        // Assert the actual and the expected state of the Sablier v2 tranched stream
        LockupTranched.StreamLT memory stream = invoiceModule.getTranchedStream({ streamId: 1 });
        assertEq(stream.sender, address(invoiceModule));
        assertEq(stream.recipient, address(space));
        assertEq(address(stream.asset), address(usdt));
        assertEq(stream.startTime, invoice.startTime);
        assertEq(stream.endTime, invoice.endTime);
        assertEq(stream.tranches.length, 4);
    }
}
