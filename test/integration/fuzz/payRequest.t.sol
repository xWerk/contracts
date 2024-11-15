// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PayRequest_Integration_Shared_Test } from "../shared/payRequest.t.sol";
import { Types } from "./../../../src/modules/payment-module/libraries/Types.sol";
import { Events } from "../../utils/Events.sol";
import { Helpers } from "../../utils/Helpers.sol";

contract PayRequest_Integration_Fuzz_Test is PayRequest_Integration_Shared_Test {
    Types.PaymentRequest paymentRequest;

    function setUp() public virtual override {
        PayRequest_Integration_Shared_Test.setUp();
    }

    function testFuzz_PayRequest(
        uint8 recurrence,
        uint8 paymentMethod,
        uint40 startTime,
        uint40 endTime,
        uint128 amount
    )
        external
        whenRequestNotNull
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
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

        // Calculate the number of payments if this is a transfer-based payment request
        (bool valid, uint40 expectedNumberOfPayments) =
            Helpers.checkFuzzedPaymentMethod(paymentMethod, recurrence, startTime, endTime);
        if (!valid) return;

        // Create a new payment request with the fuzzed payment method
        paymentRequest = Types.PaymentRequest({
            wasCanceled: false,
            wasAccepted: false,
            startTime: startTime,
            endTime: endTime,
            recipient: address(space),
            config: Types.Config({
                recurrence: Types.Recurrence(recurrence),
                method: Types.Method(paymentMethod),
                paymentsLeft: expectedNumberOfPayments,
                amount: amount,
                asset: address(usdt),
                streamId: 0
            })
        });

        // Create the calldata for the {InvoiceModule} execution
        bytes memory data = abi.encodeWithSignature(
            "createRequest((bool,bool,uint40,uint40,address,(uint8,uint8,uint40,address,uint128,uint256)))",
            paymentRequest
        );

        uint256 paymentRequestId = _nextRequestId;

        // Make Eve the caller to create the fuzzed  paymentRequest
        vm.startPrank({ msgSender: users.eve });

        // Create the fuzzed paymentRequest
        space.execute({ module: address(paymentModule), value: 0, data: data });

        // Mint enough USDT to the payer's address to be able to pay the payment request
        deal({ token: address(usdt), to: users.bob, give: paymentRequest.config.amount });

        // Make payer the caller to pay for the fuzzed paymentRequest
        vm.startPrank({ msgSender: users.bob });

        // Approve the {InvoiceModule} to transfer the USDT tokens on payer's behalf
        usdt.approve({ spender: address(paymentModule), amount: paymentRequest.config.amount });

        // Store the USDT balances of the payer and recipient before paying the payment request
        uint256 balanceOfPayerBefore = usdt.balanceOf(users.bob);
        uint256 balanceOfRecipientBefore = usdt.balanceOf(address(space));

        uint256 streamId = paymentMethod == 0 ? 0 : 1;
        uint40 expectedNumberOfPaymentsLeft = expectedNumberOfPayments > 0 ? expectedNumberOfPayments - 1 : 0;

        Types.Status expectedRequestStatus = expectedNumberOfPaymentsLeft == 0
            && paymentRequest.config.method == Types.Method.Transfer ? Types.Status.Paid : Types.Status.Accepted;

        // Expect the {RequestPaid} event to be emitted
        vm.expectEmit();
        emit Events.RequestPaid({
            requestId: paymentRequestId,
            payer: users.bob,
            config: Types.Config({
                method: paymentRequest.config.method,
                recurrence: paymentRequest.config.recurrence,
                paymentsLeft: expectedNumberOfPaymentsLeft,
                asset: paymentRequest.config.asset,
                amount: paymentRequest.config.amount,
                streamId: streamId
            })
        });

        // Run the test
        paymentModule.payRequest({ requestId: paymentRequestId });

        // Assert the actual and the expected state of the payment request
        Types.PaymentRequest memory actualRequest = paymentModule.getRequest({ requestId: paymentRequestId });
        Types.Status actualRequestStatus = paymentModule.statusOf({ requestId: paymentRequestId });

        assertEq(uint8(actualRequestStatus), uint8(expectedRequestStatus));
        assertEq(actualRequest.config.paymentsLeft, expectedNumberOfPaymentsLeft);

        // Assert the actual and expected balances of the payer and recipient
        assertEq(usdt.balanceOf(users.bob), balanceOfPayerBefore - paymentRequest.config.amount);
        if (paymentRequest.config.method == Types.Method.Transfer) {
            assertEq(usdt.balanceOf(address(space)), balanceOfRecipientBefore + paymentRequest.config.amount);
        } else {
            assertEq(usdt.balanceOf(address(space)), balanceOfRecipientBefore);
        }
    }
}
