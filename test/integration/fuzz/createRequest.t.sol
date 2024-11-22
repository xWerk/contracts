// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CreateRequest_Integration_Shared_Test } from "../shared/createRequest.t.sol";
import { Types } from "./../../../src/modules/payment-module/libraries/Types.sol";
import { Helpers } from "../../utils/Helpers.sol";
import { Events } from "../../utils/Events.sol";

contract CreateRequest_Integration_Fuzz_Test is CreateRequest_Integration_Shared_Test {
    Types.PaymentRequest paymentRequest;

    function setUp() public virtual override {
        CreateRequest_Integration_Shared_Test.setUp();

        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });
    }

    function testFuzz_CreateRequest(
        uint8 recurrence,
        uint8 paymentMethod,
        address recipient,
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
        // Assume the payment method is within Types.Method enum values (Transfer, LinearStream, TranchedStream) (0, 1, 2)
        vm.assume(paymentMethod < 3);
        vm.assume(recipient != address(0) && recipient != address(this));
        vm.assume(startTime >= uint40(block.timestamp) && startTime < endTime);
        vm.assume(amount > 0);

        // Calculate the number of payments if this is a transfer-based payment request
        (bool valid, uint40 numberOfPayments) =
            Helpers.checkFuzzedPaymentMethod(paymentMethod, recurrence, startTime, endTime);
        if (!valid) return;

        // Create a new payment request with a transfer-based payment
        paymentRequest = Types.PaymentRequest({
            wasCanceled: false,
            wasAccepted: false,
            startTime: startTime,
            endTime: endTime,
            recipient: recipient,
            config: Types.Config({
                recurrence: Types.Recurrence(recurrence),
                method: Types.Method(paymentMethod),
                paymentsLeft: numberOfPayments,
                amount: amount,
                asset: address(usdt),
                streamId: 0
            })
        });

        // Create the calldata for the {PaymentModule} execution
        bytes memory data = abi.encodeWithSignature(
            "createRequest((bool,bool,uint40,uint40,address,(uint8,uint8,uint40,address,uint128,uint256)))",
            paymentRequest
        );

        // Expect the module call to emit an {RequestCreated} event
        vm.expectEmit();
        emit Events.RequestCreated({
            requestId: 1,
            recipient: paymentRequest.recipient,
            startTime: paymentRequest.startTime,
            endTime: paymentRequest.endTime,
            config: paymentRequest.config
        });

        // Expect the {Space} contract to emit a {ModuleExecutionSucceded} event
        vm.expectEmit();
        emit Events.ModuleExecutionSucceded({ module: address(paymentModule), value: 0, data: data });

        // Run the test
        space.execute({ module: address(paymentModule), value: 0, data: data });

        // Assert the actual and expected paymentRequest state
        Types.PaymentRequest memory actualRequest = paymentModule.getRequest({ requestId: 1 });
        Types.Status paymentRequestStatus = paymentModule.statusOf({ requestId: 1 });

        assertEq(actualRequest.recipient, paymentRequest.recipient);
        assertEq(uint8(paymentRequestStatus), uint8(Types.Status.Pending));
        assertEq(actualRequest.startTime, paymentRequest.startTime);
        assertEq(actualRequest.endTime, paymentRequest.endTime);
        assertEq(uint8(actualRequest.config.method), uint8(paymentRequest.config.method));
        assertEq(uint8(actualRequest.config.recurrence), uint8(paymentRequest.config.recurrence));
        assertEq(actualRequest.config.asset, paymentRequest.config.asset);
        assertEq(actualRequest.config.amount, paymentRequest.config.amount);
        assertEq(actualRequest.config.streamId, 0);
        assertEq(actualRequest.config.paymentsLeft, paymentRequest.config.paymentsLeft);
    }
}
