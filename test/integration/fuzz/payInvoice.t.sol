// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PayInvoice_Integration_Shared_Test } from "../shared/payInvoice.t.sol";
import { Types } from "./../../../src/modules/invoice-module/libraries/Types.sol";
import { Events } from "../../utils/Events.sol";
import { Helpers } from "../../utils/Helpers.sol";

contract PayInvoice_Integration_Fuzz_Test is PayInvoice_Integration_Shared_Test {
    Types.Invoice invoice;

    function setUp() public virtual override {
        PayInvoice_Integration_Shared_Test.setUp();
    }

    function testFuzz_PayInvoice(
        uint8 recurrence,
        uint8 paymentMethod,
        uint40 startTime,
        uint40 endTime,
        uint128 amount
    )
        external
        whenInvoiceNotNull
        whenInvoiceNotAlreadyPaid
        whenInvoiceNotCanceled
        givenPaymentMethodTransfer
        givenPaymentAmountInNativeToken
        whenPaymentAmountEqualToInvoiceValue
        whenNativeTokenPaymentSucceeds
    {
        // Discard bad fuzz inputs
        // Assume recurrence is within Types.Recurrence enum values (OneOff, Weekly, Monthly, Yearly) (0, 1, 2, 3)
        vm.assume(recurrence < 4);
        // Assume recurrence is within Types.Method enum values (Transfer, LinearStream, TranchedStream) (0, 1, 2)
        vm.assume(paymentMethod < 3);
        vm.assume(startTime >= uint40(block.timestamp) && startTime < endTime);
        vm.assume(amount > 0);

        // Calculate the number of payments if this is a transfer-based invoice
        (bool valid, uint40 numberOfPayments) =
            Helpers.checkFuzzedPaymentMethod(paymentMethod, recurrence, startTime, endTime);
        if (!valid) return;

        // Create a new invoice with the fuzzed payment method
        invoice = Types.Invoice({
            status: Types.Status.Pending,
            startTime: startTime,
            endTime: endTime,
            payment: Types.Payment({
                recurrence: Types.Recurrence(recurrence),
                method: Types.Method(paymentMethod),
                paymentsLeft: numberOfPayments,
                amount: amount,
                asset: address(usdt),
                streamId: 0
            })
        });

        // Create the calldata for the {InvoiceModule} execution
        bytes memory data = abi.encodeWithSignature(
            "createInvoice((uint8,uint40,uint40,(uint8,uint8,uint40,address,uint128,uint256)))", invoice
        );

        uint256 invoiceId = _nextInvoiceId;

        // Make Eve the caller to create the fuzzed  invoice
        vm.startPrank({ msgSender: users.eve });

        // Create the fuzzed invoice
        space.execute({ module: address(invoiceModule), value: 0, data: data });

        // Mint enough USDT to the payer's address to be able to pay the invoice
        deal({ token: address(usdt), to: users.bob, give: invoice.payment.amount });

        // Make payer the caller to pay for the fuzzed invoice
        vm.startPrank({ msgSender: users.bob });

        // Approve the {InvoiceModule} to transfer the USDT tokens on payer's behalf
        usdt.approve({ spender: address(invoiceModule), amount: invoice.payment.amount });

        // Store the USDT balances of the payer and recipient before paying the invoice
        uint256 balanceOfPayerBefore = usdt.balanceOf(users.bob);
        uint256 balanceOfRecipientBefore = usdt.balanceOf(address(space));

        uint256 streamId = paymentMethod == 0 ? 0 : 1;
        numberOfPayments = numberOfPayments > 0 ? numberOfPayments - 1 : 0;

        Types.Status expectedInvoiceStatus = numberOfPayments == 0 && invoice.payment.method == Types.Method.Transfer
            ? Types.Status.Paid
            : Types.Status.Ongoing;

        // Expect the {InvoicePaid} event to be emitted
        vm.expectEmit();
        emit Events.InvoicePaid({
            id: invoiceId,
            payer: users.bob,
            status: expectedInvoiceStatus,
            payment: Types.Payment({
                method: invoice.payment.method,
                recurrence: invoice.payment.recurrence,
                paymentsLeft: numberOfPayments,
                asset: invoice.payment.asset,
                amount: invoice.payment.amount,
                streamId: streamId
            })
        });

        // Run the test
        invoiceModule.payInvoice({ id: invoiceId });

        // Assert the actual and the expected state of the invoice
        Types.Invoice memory actualInvoice = invoiceModule.getInvoice({ id: invoiceId });
        assertEq(uint8(actualInvoice.status), uint8(expectedInvoiceStatus));
        assertEq(actualInvoice.payment.paymentsLeft, numberOfPayments);

        // Assert the actual and expected balances of the payer and recipient
        assertEq(usdt.balanceOf(users.bob), balanceOfPayerBefore - invoice.payment.amount);
        if (invoice.payment.method == Types.Method.Transfer) {
            assertEq(usdt.balanceOf(address(space)), balanceOfRecipientBefore + invoice.payment.amount);
        } else {
            assertEq(usdt.balanceOf(address(space)), balanceOfRecipientBefore);
        }
    }
}
