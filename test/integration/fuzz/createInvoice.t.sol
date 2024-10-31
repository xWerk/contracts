// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CreateInvoice_Integration_Shared_Test } from "../shared/createInvoice.t.sol";
import { Types } from "./../../../src/modules/invoice-module/libraries/Types.sol";
import { Helpers } from "../../utils/Helpers.sol";
import { Events } from "../../utils/Events.sol";

contract CreateInvoice_Integration_Fuzz_Test is CreateInvoice_Integration_Shared_Test {
    Types.Invoice invoice;

    function setUp() public virtual override {
        CreateInvoice_Integration_Shared_Test.setUp();

        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });
    }

    function testFuzz_CreateInvoice(
        uint8 recurrence,
        uint8 paymentMethod,
        uint40 startTime,
        uint40 endTime,
        uint128 amount
    )
        external
        whenCallerContract
        whenCompliantSpace
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        whenPaymentAssetNotNativeToken
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

        // Create a new invoice with a transfer-based payment
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

        // Expect the module call to emit an {InvoiceCreated} event
        vm.expectEmit();
        emit Events.InvoiceCreated({
            id: 1,
            recipient: address(space),
            status: Types.Status.Pending,
            startTime: invoice.startTime,
            endTime: invoice.endTime,
            payment: invoice.payment
        });

        // Expect the {Space} contract to emit a {ModuleExecutionSucceded} event
        vm.expectEmit();
        emit Events.ModuleExecutionSucceded({ module: address(invoiceModule), value: 0, data: data });

        // Run the test
        space.execute({ module: address(invoiceModule), value: 0, data: data });

        // Assert the actual and expected invoice state
        Types.Invoice memory actualInvoice = invoiceModule.getInvoice({ id: 1 });
        address actualRecipient = invoiceModule.ownerOf(1);

        assertEq(actualRecipient, address(space));
        assertEq(uint8(actualInvoice.status), uint8(Types.Status.Pending));
        assertEq(actualInvoice.startTime, invoice.startTime);
        assertEq(actualInvoice.endTime, invoice.endTime);
        assertEq(uint8(actualInvoice.payment.method), uint8(invoice.payment.method));
        assertEq(uint8(actualInvoice.payment.recurrence), uint8(invoice.payment.recurrence));
        assertEq(actualInvoice.payment.asset, invoice.payment.asset);
        assertEq(actualInvoice.payment.amount, invoice.payment.amount);
        assertEq(actualInvoice.payment.streamId, 0);
        assertEq(actualInvoice.payment.paymentsLeft, invoice.payment.paymentsLeft);
    }
}
