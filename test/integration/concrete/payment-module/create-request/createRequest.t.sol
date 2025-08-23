// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Types } from "src/modules/payment-module/libraries/Types.sol";
import { Errors } from "src/modules/payment-module/libraries/Errors.sol";
import { IPaymentModule } from "src/modules/payment-module/interfaces/IPaymentModule.sol";
import { ISpace } from "src/interfaces/ISpace.sol";
import { CreateRequest_Integration_Shared_Test } from "test/integration/shared/createRequest.t.sol";
import { Constants } from "test/utils/Constants.sol";

contract CreateRequest_Integration_Concret_Test is CreateRequest_Integration_Shared_Test {
    Types.PaymentRequest paymentRequest;

    function setUp() public virtual override {
        CreateRequest_Integration_Shared_Test.setUp();
    }

    function test_RevertWhen_ZeroAddressRecipient() external {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a one-off transfer payment request with zero address recipient to simulate error
        paymentRequest = createPaymentRequestWithOneOffTransfer({ asset: address(usdt), recipient: address(0) });

        // Create the calldata for the Payment Module execution
        bytes memory data = abi.encodeWithSignature(
            "createRequest((bool,bool,uint40,uint40,address,(bool,uint8,uint8,uint40,address,uint128,uint256)))",
            paymentRequest
        );

        // Expect the call to revert with the {InvalidZeroAddressRecipient} error
        vm.expectRevert(Errors.InvalidZeroAddressRecipient.selector);

        // Run the test
        space.execute({ module: address(paymentModule), value: 0, data: data });
    }

    function test_RevertWhen_ZeroPaymentAmount() external whenNotZeroAddress {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a one-off transfer payment request
        paymentRequest = createPaymentRequestWithOneOffTransfer({ asset: address(usdt), recipient: address(space) });

        // Set the payment amount to zero to simulate the error
        paymentRequest.config.amount = 0;

        // Create the calldata for the Payment Module execution
        bytes memory data = abi.encodeWithSignature(
            "createRequest((bool,bool,uint40,uint40,address,(bool,uint8,uint8,uint40,address,uint128,uint256)))",
            paymentRequest
        );

        // Expect the call to revert with the {ZeroPaymentAmount} error
        vm.expectRevert(Errors.ZeroPaymentAmount.selector);

        // Run the test
        space.execute({ module: address(paymentModule), value: 0, data: data });
    }

    function test_RevertWhen_StartTimeGreaterThanEndTime() external whenNotZeroAddress whenNonZeroPaymentAmount {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a one-off transfer payment request
        paymentRequest = createPaymentRequestWithOneOffTransfer({ asset: address(usdt), recipient: address(space) });

        // Set the start time to be the current timestamp and the end time one second earlier
        paymentRequest.startTime = uint40(block.timestamp);
        paymentRequest.endTime = uint40(block.timestamp) - 1;

        // Create the calldata for the Payment Module execution
        bytes memory data = abi.encodeWithSignature(
            "createRequest((bool,bool,uint40,uint40,address,(bool,uint8,uint8,uint40,address,uint128,uint256)))",
            paymentRequest
        );

        // Expect the call to revert with the {StartTimeGreaterThanEndTime} error
        vm.expectRevert(Errors.StartTimeGreaterThanEndTime.selector);

        // Run the test
        space.execute({ module: address(paymentModule), value: 0, data: data });
    }

    function test_RevertWhen_EndTimeInThePast()
        external
        whenNotZeroAddress
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a one-off transfer payment request
        paymentRequest = createPaymentRequestWithOneOffTransfer({ asset: address(usdt), recipient: address(space) });

        // Set the block.timestamp to 1641070800
        vm.warp(1_641_070_800);

        // Set the start time to be the lower than the end time so the 'start time lower than end time' passes
        // but set the end time in the past to get the {EndTimeInThePast} revert
        paymentRequest.startTime = uint40(block.timestamp) - 2 days;
        paymentRequest.endTime = uint40(block.timestamp) - 1 days;

        // Create the calldata for the Payment Module execution
        bytes memory data = abi.encodeWithSignature(
            "createRequest((bool,bool,uint40,uint40,address,(bool,uint8,uint8,uint40,address,uint128,uint256)))",
            paymentRequest
        );

        // Expect the call to revert with the {EndTimeInThePast} error
        vm.expectRevert(Errors.EndTimeInThePast.selector);

        // Run the test
        space.execute({ module: address(paymentModule), value: 0, data: data });
    }

    function test_CreateRequest_PaymentMethodOneOffTransfer()
        external
        whenNotZeroAddress
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenPaymentMethodOneOffTransfer
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a recurring transfer payment request that must be paid on a monthly basis
        // Hence, the interval between the start and end time must be at least 1 month
        paymentRequest = createPaymentRequestWithOneOffTransfer({ asset: address(usdt), recipient: address(space) });

        // Create the calldata for the Payment Module execution
        bytes memory data = abi.encodeWithSignature(
            "createRequest((bool,bool,uint40,uint40,address,(bool,uint8,uint8,uint40,address,uint128,uint256)))",
            paymentRequest
        );

        // Expect the module call to emit an {RequestCreated} event
        vm.expectEmit();
        emit IPaymentModule.RequestCreated({
            requestId: 1,
            recipient: address(space),
            startTime: paymentRequest.startTime,
            endTime: paymentRequest.endTime,
            config: paymentRequest.config
        });

        // Expect the {Space} contract to emit a {ModuleExecutionSucceded} event
        vm.expectEmit();
        emit ISpace.ModuleExecutionSucceded({ module: address(paymentModule), value: 0, data: data });

        // Run the test
        space.execute({ module: address(paymentModule), value: 0, data: data });

        // Assert the actual and expected paymentRequest state
        Types.PaymentRequest memory actualRequest = paymentModule.getRequest({ requestId: 1 });
        Types.Status paymentRequestStatus = paymentModule.statusOf({ requestId: 1 });

        assertEq(actualRequest.recipient, address(space));
        assertEq(uint8(paymentRequestStatus), uint8(Types.Status.Pending));
        assertEq(actualRequest.startTime, paymentRequest.startTime);
        assertEq(actualRequest.endTime, paymentRequest.endTime);
        assertEq(uint8(actualRequest.config.method), uint8(Types.Method.Transfer));
        assertEq(uint8(actualRequest.config.recurrence), uint8(Types.Recurrence.OneOff));
        assertEq(actualRequest.config.paymentsLeft, 1);
        assertEq(actualRequest.config.asset, paymentRequest.config.asset);
        assertEq(actualRequest.config.amount, paymentRequest.config.amount);
        assertEq(actualRequest.config.streamId, 0);
    }

    function test_RevertWhen_OnlyTransferAllowedForCustomRecurrence()
        external
        whenNotZeroAddress
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenCustomPaymentRecurrence
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a one-off transfer payment request
        paymentRequest = createPaymentWithCustomNoOfTransfers({ asset: address(usdt), recipient: address(space) });

        // Alter the payment method to be a linear stream
        paymentRequest.config.method = Types.Method.LinearStream;

        // Create the calldata for the {PaymentModule} execution
        bytes memory data = abi.encodeWithSignature(
            "createRequest((bool,bool,uint40,uint40,address,(bool,uint8,uint8,uint40,address,uint128,uint256)))",
            paymentRequest
        );

        // Expect the call to revert with the {OnlyTransferAllowedForCustomRecurrence} error
        vm.expectRevert(Errors.OnlyTransferAllowedForCustomRecurrence.selector);

        // Run the test
        space.execute({ module: address(paymentModule), value: 0, data: data });
    }

    function test_CreateRequest_CustomRecurrence()
        external
        whenNotZeroAddress
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenCustomPaymentRecurrence
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a new payment request with an unlimited number of USDT payments
        paymentRequest = createPaymentWithCustomNoOfTransfers({ asset: address(usdt), recipient: address(space) });

        // Create the calldata for the Payment Module execution
        bytes memory data = abi.encodeWithSignature(
            "createRequest((bool,bool,uint40,uint40,address,(bool,uint8,uint8,uint40,address,uint128,uint256)))",
            paymentRequest
        );

        // Expect the module call to emit an {RequestCreated} event
        vm.expectEmit();
        emit IPaymentModule.RequestCreated({
            requestId: 1,
            recipient: address(space),
            startTime: paymentRequest.startTime,
            endTime: paymentRequest.endTime,
            config: paymentRequest.config
        });

        // Expect the {Space} contract to emit a {ModuleExecutionSucceded} event
        vm.expectEmit();
        emit ISpace.ModuleExecutionSucceded({ module: address(paymentModule), value: 0, data: data });

        // Run the test
        space.execute({ module: address(paymentModule), value: 0, data: data });

        // Assert the actual and expected paymentRequest state
        Types.PaymentRequest memory actualRequest = paymentModule.getRequest({ requestId: 1 });
        Types.Status paymentRequestStatus = paymentModule.statusOf({ requestId: 1 });

        assertEq(actualRequest.recipient, address(space));
        assertEq(uint8(paymentRequestStatus), uint8(Types.Status.Pending));
        assertEq(actualRequest.startTime, paymentRequest.startTime);
        assertEq(actualRequest.endTime, paymentRequest.endTime);
        assertEq(uint8(actualRequest.config.method), uint8(Types.Method.Transfer));
        assertEq(uint8(actualRequest.config.recurrence), uint8(Types.Recurrence.Custom));
        assertEq(actualRequest.config.asset, paymentRequest.config.asset);
        assertEq(actualRequest.config.amount, paymentRequest.config.amount);
        assertEq(actualRequest.config.paymentsLeft, paymentRequest.config.paymentsLeft);
        assertEq(actualRequest.config.streamId, 0);
    }

    function test_RevertWhen_PaymentMethodRecurringTransfer_PaymentIntervalTooShortForSelectedRecurrence()
        external
        whenNotZeroAddress
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenPaymentMethodRecurringTransfer
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a recurring transfer payment request that must be paid on a monthly basis
        // Hence, the interval between the start and end time must be at least 1 month
        paymentRequest =
            createPaymentWithRecurringTransfer({ recurrence: Types.Recurrence.Monthly, recipient: address(space) });

        // Alter the end time to be 3 weeks from now
        paymentRequest.endTime = uint40(block.timestamp) + 3 weeks;

        // Create the calldata for the Payment Module execution
        bytes memory data = abi.encodeWithSignature(
            "createRequest((bool,bool,uint40,uint40,address,(bool,uint8,uint8,uint40,address,uint128,uint256)))",
            paymentRequest
        );

        // Expect the call to revert with the {PaymentIntervalTooShortForSelectedRecurrence} error
        vm.expectRevert(Errors.PaymentIntervalTooShortForSelectedRecurrence.selector);

        // Run the test
        space.execute({ module: address(paymentModule), value: 0, data: data });
    }

    function test_CreateRequest_RecurringTransfer()
        external
        whenNotZeroAddress
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenPaymentMethodRecurringTransfer
        whenPaymentIntervalLongEnough
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a recurring transfer payment request that must be paid on weekly basis
        paymentRequest =
            createPaymentWithRecurringTransfer({ recurrence: Types.Recurrence.Weekly, recipient: address(space) });

        // Create the calldata for the Payment Module execution
        bytes memory data = abi.encodeWithSignature(
            "createRequest((bool,bool,uint40,uint40,address,(bool,uint8,uint8,uint40,address,uint128,uint256)))",
            paymentRequest
        );

        // Expect the module call to emit an {RequestCreated} event
        vm.expectEmit();
        emit IPaymentModule.RequestCreated({
            requestId: 1,
            recipient: address(space),
            startTime: paymentRequest.startTime,
            endTime: paymentRequest.endTime,
            config: paymentRequest.config
        });

        // Expect the {Space} contract to emit a {ModuleExecutionSucceded} event
        vm.expectEmit();
        emit ISpace.ModuleExecutionSucceded({ module: address(paymentModule), value: 0, data: data });

        // Run the test
        space.execute({ module: address(paymentModule), value: 0, data: data });

        // Assert the actual and expected paymentRequest state
        Types.PaymentRequest memory actualRequest = paymentModule.getRequest({ requestId: 1 });
        Types.Status paymentRequestStatus = paymentModule.statusOf({ requestId: 1 });

        assertEq(actualRequest.recipient, address(space));
        assertEq(uint8(paymentRequestStatus), uint8(Types.Status.Pending));
        assertEq(actualRequest.startTime, paymentRequest.startTime);
        assertEq(actualRequest.endTime, paymentRequest.endTime);
        assertEq(uint8(actualRequest.config.method), uint8(Types.Method.Transfer));
        assertEq(uint8(actualRequest.config.recurrence), uint8(Types.Recurrence.Weekly));
        assertEq(actualRequest.config.paymentsLeft, 4);
        assertEq(actualRequest.config.asset, paymentRequest.config.asset);
        assertEq(actualRequest.config.amount, paymentRequest.config.amount);
        assertEq(actualRequest.config.streamId, 0);
    }

    function test_RevertWhen_PaymentMethodTranchedStream_RecurrenceSetToOneOff()
        external
        whenNotZeroAddress
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenPaymentMethodTranchedStream
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a new paymentRequest with a tranched stream payment
        paymentRequest =
            createPaymentRequestWithTranchedStream({ recurrence: Types.Recurrence.Weekly, recipient: address(space) });

        // Alter the payment recurrence by setting it to one-off
        paymentRequest.config.recurrence = Types.Recurrence.OneOff;

        // Expect the call to revert with the {TranchedStreamInvalidOneOffRecurence} error
        vm.expectRevert(Errors.TranchedStreamInvalidOneOffRecurence.selector);

        // Create the calldata for the Payment Module execution
        bytes memory data = abi.encodeWithSignature(
            "createRequest((bool,bool,uint40,uint40,address,(bool,uint8,uint8,uint40,address,uint128,uint256)))",
            paymentRequest
        );

        // Run the test
        space.execute({ module: address(paymentModule), value: 0, data: data });
    }

    function test_RevertWhen_PaymentMethodTranchedStream_PaymentIntervalTooShortForSelectedRecurrence()
        external
        whenNotZeroAddress
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenPaymentMethodTranchedStream
        whenTranchedStreamWithGoodRecurring
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a new paymentRequest with a tranched stream payment
        paymentRequest =
            createPaymentRequestWithTranchedStream({ recurrence: Types.Recurrence.Monthly, recipient: address(space) });

        // Alter the end time to be 3 weeks from now
        paymentRequest.endTime = uint40(block.timestamp) + 3 weeks;

        // Expect the call to revert with the {PaymentIntervalTooShortForSelectedRecurrence} error
        vm.expectRevert(Errors.PaymentIntervalTooShortForSelectedRecurrence.selector);

        // Create the calldata for the Payment Module execution
        bytes memory data = abi.encodeWithSignature(
            "createRequest((bool,bool,uint40,uint40,address,(bool,uint8,uint8,uint40,address,uint128,uint256)))",
            paymentRequest
        );

        // Run the test
        space.execute({ module: address(paymentModule), value: 0, data: data });
    }

    function test_RevertWhen_PaymentMethodTranchedStream_PaymentAssetNativeToken()
        external
        whenNotZeroAddress
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenPaymentMethodTranchedStream
        whenTranchedStreamWithGoodRecurring
        whenPaymentIntervalLongEnough
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a new paymentRequest with a linear stream payment
        paymentRequest =
            createPaymentRequestWithTranchedStream({ recurrence: Types.Recurrence.Weekly, recipient: address(space) });

        // Alter the payment asset by setting it to
        paymentRequest.config.asset = Constants.NATIVE_TOKEN;

        // Expect the call to revert with the {OnlyERC20StreamsAllowed} error
        vm.expectRevert(Errors.OnlyERC20StreamsAllowed.selector);

        // Create the calldata for the Payment Module execution
        bytes memory data = abi.encodeWithSignature(
            "createRequest((bool,bool,uint40,uint40,address,(bool,uint8,uint8,uint40,address,uint128,uint256)))",
            paymentRequest
        );

        // Run the test
        space.execute({ module: address(paymentModule), value: 0, data: data });
    }

    function test_CreateRequest_Tranched()
        external
        whenNotZeroAddress
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenPaymentMethodTranchedStream
        whenPaymentAssetNotNativeToken
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a new paymentRequest with a tranched stream payment
        paymentRequest =
            createPaymentRequestWithTranchedStream({ recurrence: Types.Recurrence.Weekly, recipient: address(space) });

        // Create the calldata for the Payment Module execution
        bytes memory data = abi.encodeWithSignature(
            "createRequest((bool,bool,uint40,uint40,address,(bool,uint8,uint8,uint40,address,uint128,uint256)))",
            paymentRequest
        );

        // Expect the module call to emit an {RequestCreated} event
        vm.expectEmit();
        emit IPaymentModule.RequestCreated({
            requestId: 1,
            recipient: address(space),
            startTime: paymentRequest.startTime,
            endTime: paymentRequest.endTime,
            config: paymentRequest.config
        });

        // Expect the {Space} contract to emit a {ModuleExecutionSucceded} event
        vm.expectEmit();
        emit ISpace.ModuleExecutionSucceded({ module: address(paymentModule), value: 0, data: data });

        // Run the test
        space.execute({ module: address(paymentModule), value: 0, data: data });

        // Assert the actual and expected paymentRequest state
        Types.PaymentRequest memory actualRequest = paymentModule.getRequest({ requestId: 1 });
        Types.Status paymentRequestStatus = paymentModule.statusOf({ requestId: 1 });

        assertEq(actualRequest.recipient, address(space));
        assertEq(uint8(paymentRequestStatus), uint8(Types.Status.Pending));
        assertEq(actualRequest.startTime, paymentRequest.startTime);
        assertEq(actualRequest.endTime, paymentRequest.endTime);
        assertEq(uint8(actualRequest.config.method), uint8(Types.Method.TranchedStream));
        assertEq(uint8(actualRequest.config.recurrence), uint8(Types.Recurrence.Weekly));
        assertEq(actualRequest.config.paymentsLeft, 1);
        assertEq(actualRequest.config.asset, paymentRequest.config.asset);
        assertEq(actualRequest.config.amount, paymentRequest.config.amount);
        assertEq(actualRequest.config.streamId, 0);
    }

    function test_RevertWhen_PaymentMethodLinearStream_PaymentAssetNativeToken()
        external
        whenNotZeroAddress
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenPaymentMethodLinearStream
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a new paymentRequest with a linear stream payment
        paymentRequest = createPaymentRequestWithLinearStream({ recipient: address(space) });

        // Alter the payment asset by setting it to
        paymentRequest.config.asset = Constants.NATIVE_TOKEN;

        // Expect the call to revert with the {OnlyERC20StreamsAllowed} error
        vm.expectRevert(Errors.OnlyERC20StreamsAllowed.selector);

        // Create the calldata for the Payment Module execution
        bytes memory data = abi.encodeWithSignature(
            "createRequest((bool,bool,uint40,uint40,address,(bool,uint8,uint8,uint40,address,uint128,uint256)))",
            paymentRequest
        );

        // Run the test
        space.execute({ module: address(paymentModule), value: 0, data: data });
    }

    function test_CreateRequest_LinearStream()
        external
        whenNotZeroAddress
        whenNonZeroPaymentAmount
        whenStartTimeLowerThanEndTime
        whenEndTimeInTheFuture
        givenPaymentMethodLinearStream
        whenPaymentAssetNotNativeToken
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create a new paymentRequest with a linear stream payment
        paymentRequest = createPaymentRequestWithLinearStream({ recipient: address(space) });

        // Create the calldata for the Payment Module execution
        bytes memory data = abi.encodeWithSignature(
            "createRequest((bool,bool,uint40,uint40,address,(bool,uint8,uint8,uint40,address,uint128,uint256)))",
            paymentRequest
        );

        // Expect the module call to emit an {RequestCreated} event
        vm.expectEmit();
        emit IPaymentModule.RequestCreated({
            requestId: 1,
            recipient: address(space),
            startTime: paymentRequest.startTime,
            endTime: paymentRequest.endTime,
            config: paymentRequest.config
        });

        // Expect the {Space} contract to emit a {ModuleExecutionSucceded} event
        vm.expectEmit();
        emit ISpace.ModuleExecutionSucceded({ module: address(paymentModule), value: 0, data: data });

        // Run the test
        space.execute({ module: address(paymentModule), value: 0, data: data });

        // Assert the actual and expected paymentRequest state
        Types.PaymentRequest memory actualRequest = paymentModule.getRequest({ requestId: 1 });
        Types.Status paymentRequestStatus = paymentModule.statusOf({ requestId: 1 });

        assertEq(actualRequest.recipient, address(space));
        assertEq(uint8(paymentRequestStatus), uint8(Types.Status.Pending));
        assertEq(actualRequest.startTime, paymentRequest.startTime);
        assertEq(actualRequest.endTime, paymentRequest.endTime);
        assertEq(uint8(actualRequest.config.method), uint8(Types.Method.LinearStream));
        assertEq(uint8(actualRequest.config.recurrence), uint8(Types.Recurrence.Weekly));
        assertEq(actualRequest.config.asset, paymentRequest.config.asset);
        assertEq(actualRequest.config.amount, paymentRequest.config.amount);
        assertEq(actualRequest.config.streamId, 0);
    }
}
