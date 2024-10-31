// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CreateInvoice_Integration_Shared_Test } from "../../../shared/createInvoice.t.sol";
import { Types } from "./../../../../../src/modules/invoice-module/libraries/Types.sol";
import { Errors } from "../../../../utils/Errors.sol";
import { Events } from "../../../../utils/Events.sol";

contract CreateInvoice_Integration_Concret_Test is CreateInvoice_Integration_Shared_Test {
    Types.Invoice invoice;

    function setUp() public virtual override {
        CreateInvoice_Integration_Shared_Test.setUp();
    }

    function test_RevertWhen_CallerNotContract() external {
        // Make Bob the caller in this test suite which is an EOA
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to revert with the {SpaceZeroCodeSize} error
        vm.expectRevert(Errors.SpaceZeroCodeSize.selector);

        // Create an one-off transfer invoice
        invoice = createInvoiceWithOneOffTransfer({ asset: address(usdt) });

        // Run the test
        invoiceModule.createInvoice(invoice);
    }

    function test_RevertWhen_NonCompliantSpace() external whenCallerContract {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create an one-off transfer invoice
        invoice = createInvoiceWithOneOffTransfer({ asset: address(usdt) });

        // Create the calldata for the Invoice Module execution
        bytes memory data = abi.encodeWithSignature(
            "createInvoice((uint8,uint40,uint40,(uint8,uint8,uint40,address,uint128,uint256)))", invoice
        );

        // Expect the call to revert with the {SpaceUnsupportedInterface} error
        vm.expectRevert(Errors.SpaceUnsupportedInterface.selector);

        // Run the test
        mockNonCompliantSpace.execute({ module: address(invoiceModule), value: 0, data: data });
    }

    function test_RevertWhen_ZeroPaymentAmount() external whenCallerContract whenCompliantSpace {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create an one-off transfer invoice
        invoice = createInvoiceWithOneOffTransfer({ asset: address(usdt) });

        // Set the payment amount to zero to simulate the error
        invoice.payment.amount = 0;

        // Create the calldata for the Invoice Module execution
        bytes memory data = abi.encodeWithSignature(
            "createInvoice((uint8,uint40,uint40,(uint8,uint8,uint40,address,uint128,uint256)))", invoice
        );

        // Expect the call to revert with the {ZeroPaymentAmount} error
        vm.expectRevert(Errors.ZeroPaymentAmount.selector);

        // Run the test
        space.execute({ module: address(invoiceModule), value: 0, data: data });
    }

    function test_RevertWhen_StartTimeGreaterThanEndTime()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonZeroPaymentAmount
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create an one-off transfer invoice
        invoice = createInvoiceWithOneOffTransfer({ asset: address(usdt) });

        // Set the start time to be the current timestamp and the end time one second earlier
        invoice.startTime = uint40(block.timestamp);
        invoice.endTime = uint40(block.timestamp) - 1;

        // Create the calldata for the Invoice Module execution
        bytes memory data = abi.encodeWithSignature(
            "createInvoice((uint8,uint40,uint40,(uint8,uint8,uint40,address,uint128,uint256)))", invoice
        );

        // Expect the call to revert with the {StartTimeGreaterThanEndTime} error
        vm.expectRevert(Errors.StartTimeGreaterThanEndTime.selector);

        // Run the test
        space.execute({ module: address(invoiceModule), value: 0, data: data });
    }

    function test_RevertWhen_EndTimeInThePast()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create an one-off transfer invoice
        invoice = createInvoiceWithOneOffTransfer({ asset: address(usdt) });

        // Set the block.timestamp to 1641070800
        vm.warp(1_641_070_800);

        // Set the start time to be the lower than the end time so the 'start time lower than end time' passes
        // but set the end time in the past to get the {EndTimeInThePast} revert
        invoice.startTime = uint40(block.timestamp) - 2 days;
        invoice.endTime = uint40(block.timestamp) - 1 days;

        // Create the calldata for the Invoice Module execution
        bytes memory data = abi.encodeWithSignature(
            "createInvoice((uint8,uint40,uint40,(uint8,uint8,uint40,address,uint128,uint256)))", invoice
        );

        // Expect the call to revert with the {EndTimeInThePast} error
        vm.expectRevert(Errors.EndTimeInThePast.selector);

        // Run the test
        space.execute({ module: address(invoiceModule), value: 0, data: data });
    }

    function test_CreateInvoice_PaymentMethodOneOffTransfer()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenPaymentMethodOneOffTransfer
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a recurring transfer invoice that must be paid on a monthly basis
        // Hence, the interval between the start and end time must be at least 1 month
        invoice = createInvoiceWithOneOffTransfer({ asset: address(usdt) });

        // Create the calldata for the Invoice Module execution
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
        address expectedRecipient = invoiceModule.ownerOf(1);

        assertEq(expectedRecipient, address(space));
        assertEq(uint8(actualInvoice.status), uint8(Types.Status.Pending));
        assertEq(actualInvoice.startTime, invoice.startTime);
        assertEq(actualInvoice.endTime, invoice.endTime);
        assertEq(uint8(actualInvoice.payment.method), uint8(Types.Method.Transfer));
        assertEq(uint8(actualInvoice.payment.recurrence), uint8(Types.Recurrence.OneOff));
        assertEq(actualInvoice.payment.paymentsLeft, 1);
        assertEq(actualInvoice.payment.asset, invoice.payment.asset);
        assertEq(actualInvoice.payment.amount, invoice.payment.amount);
        assertEq(actualInvoice.payment.streamId, 0);
    }

    function test_RevertWhen_PaymentMethodRecurringTransfer_PaymentIntervalTooShortForSelectedRecurrence()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenPaymentMethodRecurringTransfer
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a recurring transfer invoice that must be paid on a monthly basis
        // Hence, the interval between the start and end time must be at least 1 month
        invoice = createInvoiceWithRecurringTransfer({ recurrence: Types.Recurrence.Monthly });

        // Alter the end time to be 3 weeks from now
        invoice.endTime = uint40(block.timestamp) + 3 weeks;

        // Create the calldata for the Invoice Module execution
        bytes memory data = abi.encodeWithSignature(
            "createInvoice((uint8,uint40,uint40,(uint8,uint8,uint40,address,uint128,uint256)))", invoice
        );

        // Expect the call to revert with the {PaymentIntervalTooShortForSelectedRecurrence} error
        vm.expectRevert(Errors.PaymentIntervalTooShortForSelectedRecurrence.selector);

        // Run the test
        space.execute({ module: address(invoiceModule), value: 0, data: data });
    }

    function test_CreateInvoice_RecurringTransfer()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenPaymentMethodRecurringTransfer
        whenPaymentIntervalLongEnough
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a recurring transfer invoice that must be paid on weekly basis
        invoice = createInvoiceWithRecurringTransfer({ recurrence: Types.Recurrence.Weekly });

        // Create the calldata for the Invoice Module execution
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
        address expectedRecipient = invoiceModule.ownerOf(1);

        assertEq(expectedRecipient, address(space));
        assertEq(uint8(actualInvoice.status), uint8(Types.Status.Pending));
        assertEq(actualInvoice.startTime, invoice.startTime);
        assertEq(actualInvoice.endTime, invoice.endTime);
        assertEq(uint8(actualInvoice.payment.method), uint8(Types.Method.Transfer));
        assertEq(uint8(actualInvoice.payment.recurrence), uint8(Types.Recurrence.Weekly));
        assertEq(actualInvoice.payment.paymentsLeft, 4);
        assertEq(actualInvoice.payment.asset, invoice.payment.asset);
        assertEq(actualInvoice.payment.amount, invoice.payment.amount);
        assertEq(actualInvoice.payment.streamId, 0);
    }

    function test_RevertWhen_PaymentMethodTranchedStream_RecurrenceSetToOneOff()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenPaymentMethodTranchedStream
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a new invoice with a tranched stream payment
        invoice = createInvoiceWithTranchedStream({ recurrence: Types.Recurrence.Weekly });

        // Alter the payment recurrence by setting it to one-off
        invoice.payment.recurrence = Types.Recurrence.OneOff;

        // Expect the call to revert with the {TranchedStreamInvalidOneOffRecurence} error
        vm.expectRevert(Errors.TranchedStreamInvalidOneOffRecurence.selector);

        // Create the calldata for the Invoice Module execution
        bytes memory data = abi.encodeWithSignature(
            "createInvoice((uint8,uint40,uint40,(uint8,uint8,uint40,address,uint128,uint256)))", invoice
        );

        // Run the test
        space.execute({ module: address(invoiceModule), value: 0, data: data });
    }

    function test_RevertWhen_PaymentMethodTranchedStream_PaymentIntervalTooShortForSelectedRecurrence()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenPaymentMethodTranchedStream
        whenTranchedStreamWithGoodRecurring
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a new invoice with a tranched stream payment
        invoice = createInvoiceWithTranchedStream({ recurrence: Types.Recurrence.Monthly });

        // Alter the end time to be 3 weeks from now
        invoice.endTime = uint40(block.timestamp) + 3 weeks;

        // Expect the call to revert with the {PaymentIntervalTooShortForSelectedRecurrence} error
        vm.expectRevert(Errors.PaymentIntervalTooShortForSelectedRecurrence.selector);

        // Create the calldata for the Invoice Module execution
        bytes memory data = abi.encodeWithSignature(
            "createInvoice((uint8,uint40,uint40,(uint8,uint8,uint40,address,uint128,uint256)))", invoice
        );

        // Run the test
        space.execute({ module: address(invoiceModule), value: 0, data: data });
    }

    function test_RevertWhen_PaymentMethodTranchedStream_PaymentAssetNativeToken()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenPaymentMethodTranchedStream
        whenTranchedStreamWithGoodRecurring
        whenPaymentIntervalLongEnough
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a new invoice with a linear stream payment
        invoice = createInvoiceWithTranchedStream({ recurrence: Types.Recurrence.Weekly });

        // Alter the payment asset by setting it to
        invoice.payment.asset = address(0);

        // Expect the call to revert with the {OnlyERC20StreamsAllowed} error
        vm.expectRevert(Errors.OnlyERC20StreamsAllowed.selector);

        // Create the calldata for the Invoice Module execution
        bytes memory data = abi.encodeWithSignature(
            "createInvoice((uint8,uint40,uint40,(uint8,uint8,uint40,address,uint128,uint256)))", invoice
        );

        // Run the test
        space.execute({ module: address(invoiceModule), value: 0, data: data });
    }

    function test_CreateInvoice_Tranched()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenPaymentMethodTranchedStream
        whenPaymentAssetNotNativeToken
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a new invoice with a tranched stream payment
        invoice = createInvoiceWithTranchedStream({ recurrence: Types.Recurrence.Weekly });

        // Create the calldata for the Invoice Module execution
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
        address expectedRecipient = invoiceModule.ownerOf(1);

        assertEq(expectedRecipient, address(space));
        assertEq(uint8(actualInvoice.status), uint8(Types.Status.Pending));
        assertEq(actualInvoice.startTime, invoice.startTime);
        assertEq(actualInvoice.endTime, invoice.endTime);
        assertEq(uint8(actualInvoice.payment.method), uint8(Types.Method.TranchedStream));
        assertEq(uint8(actualInvoice.payment.recurrence), uint8(Types.Recurrence.Weekly));
        assertEq(actualInvoice.payment.paymentsLeft, 0);
        assertEq(actualInvoice.payment.asset, invoice.payment.asset);
        assertEq(actualInvoice.payment.amount, invoice.payment.amount);
        assertEq(actualInvoice.payment.streamId, 0);
    }

    function test_RevertWhen_PaymentMethodLinearStream_PaymentAssetNativeToken()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenPaymentMethodLinearStream
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a new invoice with a linear stream payment
        invoice = createInvoiceWithLinearStream();

        // Alter the payment asset by setting it to
        invoice.payment.asset = address(0);

        // Expect the call to revert with the {OnlyERC20StreamsAllowed} error
        vm.expectRevert(Errors.OnlyERC20StreamsAllowed.selector);

        // Create the calldata for the Invoice Module execution
        bytes memory data = abi.encodeWithSignature(
            "createInvoice((uint8,uint40,uint40,(uint8,uint8,uint40,address,uint128,uint256)))", invoice
        );

        // Run the test
        space.execute({ module: address(invoiceModule), value: 0, data: data });
    }

    function test_CreateInvoice_LinearStream()
        external
        whenCallerContract
        whenCompliantSpace
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenPaymentMethodLinearStream
        whenPaymentAssetNotNativeToken
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a new invoice with a linear stream payment
        invoice = createInvoiceWithLinearStream();

        // Create the calldata for the Invoice Module execution
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
        address expectedRecipient = invoiceModule.ownerOf(1);

        assertEq(expectedRecipient, address(space));
        assertEq(uint8(actualInvoice.status), uint8(Types.Status.Pending));
        assertEq(actualInvoice.startTime, invoice.startTime);
        assertEq(actualInvoice.endTime, invoice.endTime);
        assertEq(uint8(actualInvoice.payment.method), uint8(Types.Method.LinearStream));
        assertEq(uint8(actualInvoice.payment.recurrence), uint8(Types.Recurrence.Weekly));
        assertEq(actualInvoice.payment.asset, invoice.payment.asset);
        assertEq(actualInvoice.payment.amount, invoice.payment.amount);
        assertEq(actualInvoice.payment.streamId, 0);
    }
}
