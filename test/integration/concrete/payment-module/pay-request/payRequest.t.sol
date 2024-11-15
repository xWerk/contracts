// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { PayRequest_Integration_Shared_Test } from "../../../shared/payRequest.t.sol";
import { Types } from "./../../../../../src/modules/payment-module/libraries/Types.sol";
import { Events } from "../../../../utils/Events.sol";
import { Errors } from "../../../../utils/Errors.sol";

import { LockupLinear, LockupTranched } from "@sablier/v2-core/src/types/DataTypes.sol";

contract PayInvoice_Integration_Concret_Test is PayRequest_Integration_Shared_Test {
    function setUp() public virtual override {
        PayRequest_Integration_Shared_Test.setUp();
    }

    function test_RevertWhen_RequestNull() external {
        // Expect the call to revert with the {NullRequest} error
        vm.expectRevert(Errors.NullRequest.selector);

        // Run the test
        paymentModule.payRequest({ requestId: 99 });
    }

    function test_RevertWhen_RequestAlreadyPaid() external whenRequestNotNull {
        // Set the one-off USDT transfer payment request as current one
        uint256 paymentRequestId = 1;

        // Make Bob the payer for the default paymentRequest
        vm.startPrank({ msgSender: users.bob });

        // Approve the {InvoiceModule} to transfer the ERC-20 token on Bob's behalf
        usdt.approve({ spender: address(paymentModule), amount: paymentRequests[paymentRequestId].config.amount });

        // Pay first the payment request
        paymentModule.payRequest({ requestId: paymentRequestId });

        // Expect the call to be reverted with the {RequestPaid} error
        vm.expectRevert(Errors.RequestPaid.selector);

        // Run the test
        paymentModule.payRequest({ requestId: paymentRequestId });
    }

    function test_RevertWhen_RequestCanceled() external whenRequestNotNull whenRequestNotAlreadyPaid {
        // Set the one-off USDT transfer payment request as current one
        uint256 paymentRequestId = 1;

        // Make Eve's space the caller in this test suite as his space is the owner of the payment request
        vm.startPrank({ msgSender: address(space) });

        // Cancel the payment request first
        paymentModule.cancelRequest({ requestId: paymentRequestId });

        // Make Bob the payer of this paymentRequest
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to be reverted with the {RequestCanceled} error
        vm.expectRevert(Errors.RequestCanceled.selector);

        // Run the test
        paymentModule.payRequest({ requestId: paymentRequestId });
    }

    function test_RevertWhen_PaymentMethodTransfer_PaymentAmountLessThanInvoiceValue()
        external
        whenRequestNotNull
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodTransfer
        givenPaymentAmountInNativeToken
    {
        // Set the one-off ETH transfer payment request as current one
        uint256 paymentRequestId = 2;

        // Make Bob the payer for the default paymentRequest
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to be reverted with the {PaymentAmountLessThanInvoiceValue} error
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.PaymentAmountLessThanInvoiceValue.selector, paymentRequests[paymentRequestId].config.amount
            )
        );

        // Run the test
        paymentModule.payRequest{ value: paymentRequests[paymentRequestId].config.amount - 1 }({
            requestId: paymentRequestId
        });
    }

    function test_RevertWhen_PaymentMethodTransfer_NativeTokenTransferFails()
        external
        whenRequestNotNull
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodTransfer
        givenPaymentAmountInNativeToken
        whenPaymentAmountEqualToInvoiceValue
    {
        // Create a mock payment request with a one-off ETH transfer from the Eve's space
        Types.PaymentRequest memory paymentRequest =
            createPaymentRequestWithOneOffTransfer({ asset: address(0), recipient: address(mockBadReceiver) });
        executeCreatePaymentRequest({ paymentRequest: paymentRequest, user: users.eve });

        uint256 paymentRequestId = _nextRequestId;

        // Make Eve's space the caller for the next call to approve & transfer the payment request NFT to a bad receiver
        //vm.startPrank({ msgSender: address(space) });

        // Approve the {InvoiceModule} to transfer the token
        //paymentModule.approve({ to: address(paymentModule), tokenrequestId: paymentRequestId });

        // Transfer the payment request to a bad receiver so we can test against `NativeTokenPaymentFailed`
        //paymentModule.transferFrom({ from: address(space), to: address(mockBadReceiver), tokenrequestId: paymentRequestId });

        // Make Bob the payer for this paymentRequest
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to be reverted with the {NativeTokenPaymentFailed} error
        vm.expectRevert(Errors.NativeTokenPaymentFailed.selector);

        // Run the test
        paymentModule.payRequest{ value: paymentRequest.config.amount }({ requestId: paymentRequestId });
    }

    function test_PayRequest_PaymentMethodTransfer_NativeToken_OneOff()
        external
        whenRequestNotNull
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodTransfer
        givenPaymentAmountInNativeToken
        whenPaymentAmountEqualToInvoiceValue
        whenNativeTokenPaymentSucceeds
    {
        // Set the one-off ETH transfer payment request as current one
        uint256 paymentRequestId = 2;

        // Make Bob the payer for the default paymentRequest
        vm.startPrank({ msgSender: users.bob });

        // Store the ETH balances of Bob and recipient before paying the payment request
        uint256 balanceOfBobBefore = address(users.bob).balance;
        uint256 balanceOfRecipientBefore = address(space).balance;

        // Expect the {RequestPaid} event to be emitted
        vm.expectEmit();
        emit Events.RequestPaid({
            requestId: paymentRequestId,
            payer: users.bob,
            config: Types.Config({
                method: paymentRequests[paymentRequestId].config.method,
                recurrence: paymentRequests[paymentRequestId].config.recurrence,
                paymentsLeft: 0,
                asset: paymentRequests[paymentRequestId].config.asset,
                amount: paymentRequests[paymentRequestId].config.amount,
                streamId: 0
            })
        });

        // Run the test
        paymentModule.payRequest{ value: paymentRequests[paymentRequestId].config.amount }({
            requestId: paymentRequestId
        });

        // Assert the actual and the expected state of the payment request
        Types.PaymentRequest memory paymentRequest = paymentModule.getRequest({ requestId: paymentRequestId });
        Types.Status paymentRequestStatus = paymentModule.statusOf({ requestId: paymentRequestId });

        assertEq(uint8(paymentRequestStatus), uint8(Types.Status.Paid));
        assertEq(paymentRequest.config.paymentsLeft, 0);

        // Assert the balances of payer and recipient
        assertEq(address(users.bob).balance, balanceOfBobBefore - paymentRequests[paymentRequestId].config.amount);
        assertEq(address(space).balance, balanceOfRecipientBefore + paymentRequests[paymentRequestId].config.amount);
    }

    function test_PayRequest_PaymentMethodTransfer_ERC20Token_Recurring()
        external
        whenRequestNotNull
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodTransfer
        givenPaymentAmountInERC20Tokens
        whenPaymentAmountEqualToInvoiceValue
    {
        // Set the recurring USDT transfer payment request as current one
        uint256 paymentRequestId = 3;

        // Make Bob the payer for the default paymentRequest
        vm.startPrank({ msgSender: users.bob });

        // Store the USDT balances of Bob and recipient before paying the payment request
        uint256 balanceOfBobBefore = usdt.balanceOf(users.bob);
        uint256 balanceOfRecipientBefore = usdt.balanceOf(address(space));

        // Approve the {InvoiceModule} to transfer the ERC-20 tokens on Bob's behalf
        usdt.approve({ spender: address(paymentModule), amount: paymentRequests[paymentRequestId].config.amount });

        // Expect the {RequestPaid} event to be emitted
        vm.expectEmit();
        emit Events.RequestPaid({
            requestId: paymentRequestId,
            payer: users.bob,
            config: Types.Config({
                method: paymentRequests[paymentRequestId].config.method,
                recurrence: paymentRequests[paymentRequestId].config.recurrence,
                paymentsLeft: 3,
                asset: paymentRequests[paymentRequestId].config.asset,
                amount: paymentRequests[paymentRequestId].config.amount,
                streamId: 0
            })
        });

        // Run the test
        paymentModule.payRequest{ value: paymentRequests[paymentRequestId].config.amount }({
            requestId: paymentRequestId
        });

        // Assert the actual and the expected state of the payment request
        Types.PaymentRequest memory paymentRequest = paymentModule.getRequest({ requestId: paymentRequestId });
        Types.Status paymentRequestStatus = paymentModule.statusOf({ requestId: paymentRequestId });

        assertEq(uint8(paymentRequestStatus), uint8(Types.Status.Accepted));
        assertEq(paymentRequest.config.paymentsLeft, 3);

        // Assert the balances of payer and recipient
        assertEq(usdt.balanceOf(users.bob), balanceOfBobBefore - paymentRequests[paymentRequestId].config.amount);
        assertEq(
            usdt.balanceOf(address(space)), balanceOfRecipientBefore + paymentRequests[paymentRequestId].config.amount
        );
    }

    function test_PayRequest_PaymentMethodLinearStream()
        external
        whenRequestNotNull
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodLinearStream
        givenPaymentAmountInERC20Tokens
        whenPaymentAmountEqualToInvoiceValue
    {
        // Set the linear USDT stream-based paymentRequest as current one
        uint256 paymentRequestId = 4;

        // Make Bob the payer for the default paymentRequest
        vm.startPrank({ msgSender: users.bob });

        // Approve the {InvoiceModule} to transfer the ERC-20 tokens on Bob's behalf
        usdt.approve({ spender: address(paymentModule), amount: paymentRequests[paymentRequestId].config.amount });

        // Expect the {RequestPaid} event to be emitted
        vm.expectEmit();
        emit Events.RequestPaid({
            requestId: paymentRequestId,
            payer: users.bob,
            config: Types.Config({
                method: paymentRequests[paymentRequestId].config.method,
                recurrence: paymentRequests[paymentRequestId].config.recurrence,
                paymentsLeft: 0,
                asset: paymentRequests[paymentRequestId].config.asset,
                amount: paymentRequests[paymentRequestId].config.amount,
                streamId: 1
            })
        });

        // Run the test
        paymentModule.payRequest{ value: paymentRequests[paymentRequestId].config.amount }({
            requestId: paymentRequestId
        });

        // Assert the actual and the expected state of the payment request
        Types.PaymentRequest memory paymentRequest = paymentModule.getRequest({ requestId: paymentRequestId });
        Types.Status paymentRequestStatus = paymentModule.statusOf({ requestId: paymentRequestId });

        assertEq(uint8(paymentRequestStatus), uint8(Types.Status.Accepted));
        assertEq(paymentRequest.config.streamId, 1);
        assertEq(paymentRequest.config.paymentsLeft, 0);

        // Assert the actual and the expected state of the Sablier v2 linear stream
        LockupLinear.StreamLL memory stream = paymentModule.getLinearStream({ streamId: 1 });
        assertEq(stream.sender, address(paymentModule));
        assertEq(stream.recipient, address(space));
        assertEq(address(stream.asset), address(usdt));
        assertEq(stream.startTime, paymentRequest.startTime);
        assertEq(stream.endTime, paymentRequest.endTime);
    }

    function test_PayRequest_PaymentMethodTranchedStream()
        external
        whenRequestNotNull
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodTranchedStream
        givenPaymentAmountInERC20Tokens
        whenPaymentAmountEqualToInvoiceValue
    {
        // Set the tranched USDT stream-based paymentRequest as current one
        uint256 paymentRequestId = 5;

        // Make Bob the payer for the default paymentRequest
        vm.startPrank({ msgSender: users.bob });

        // Approve the {InvoiceModule} to transfer the ERC-20 tokens on Bob's behalf
        usdt.approve({ spender: address(paymentModule), amount: paymentRequests[paymentRequestId].config.amount });

        // Expect the {RequestPaid} event to be emitted
        vm.expectEmit();
        emit Events.RequestPaid({
            requestId: paymentRequestId,
            payer: users.bob,
            config: Types.Config({
                method: paymentRequests[paymentRequestId].config.method,
                recurrence: paymentRequests[paymentRequestId].config.recurrence,
                paymentsLeft: 0,
                asset: paymentRequests[paymentRequestId].config.asset,
                amount: paymentRequests[paymentRequestId].config.amount,
                streamId: 1
            })
        });

        // Run the test
        paymentModule.payRequest{ value: paymentRequests[paymentRequestId].config.amount }({
            requestId: paymentRequestId
        });

        // Assert the actual and the expected state of the payment request
        Types.PaymentRequest memory paymentRequest = paymentModule.getRequest({ requestId: paymentRequestId });
        Types.Status paymentRequestStatus = paymentModule.statusOf({ requestId: paymentRequestId });

        assertEq(uint8(paymentRequestStatus), uint8(Types.Status.Accepted));
        assertEq(paymentRequest.config.streamId, 1);
        assertEq(paymentRequest.config.paymentsLeft, 0);

        // Assert the actual and the expected state of the Sablier v2 tranched stream
        LockupTranched.StreamLT memory stream = paymentModule.getTranchedStream({ streamId: 1 });
        assertEq(stream.sender, address(paymentModule));
        assertEq(stream.recipient, address(space));
        assertEq(address(stream.asset), address(usdt));
        assertEq(stream.startTime, paymentRequest.startTime);
        assertEq(stream.endTime, paymentRequest.endTime);
        assertEq(stream.tranches.length, 4);
    }
}
