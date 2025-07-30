// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Types } from "src/modules/payment-module/libraries/Types.sol";
import { IPaymentModule } from "src/modules/payment-module/interfaces/IPaymentModule.sol";
import { Errors } from "src/modules/payment-module/libraries/Errors.sol";
import { Constants } from "test/utils/Constants.sol";
import { PayRequest_Integration_Shared_Test } from "test/integration/shared/payRequest.t.sol";
import { ISablierLockup } from "@sablier/lockup/src/interfaces/ISablierLockup.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Broker, Lockup, LockupTranched } from "@sablier/lockup/src/types/DataTypes.sol";
import { Helpers } from "test/utils/Helpers.sol";

contract PayPayment_Integration_Concret_Test is PayRequest_Integration_Shared_Test {
    function setUp() public virtual override {
        PayRequest_Integration_Shared_Test.setUp();
    }

    function test_RevertWhen_RequestNull() external {
        // Expect the call to revert with the {NullRequest} error
        vm.expectRevert(Errors.NullRequest.selector);

        // Run the test
        paymentModule.payRequest({ requestId: 99 });
    }

    function test_RevertWhen_RequestExpired() external whenRequestNotNull {
        // Set the unlimited USDT transfers payment request as current one
        uint256 paymentRequestId = 6;

        // Set the block.timestamp to be greater than the payment request end time
        vm.warp(paymentRequests[paymentRequestId].endTime + 1);

        // Make Bob the payer of this paymentRequest
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to be reverted with the {RequestExpired} error
        vm.expectRevert(Errors.RequestExpired.selector);

        // Run the test
        paymentModule.payRequest({ requestId: paymentRequestId });
    }

    function test_RevertWhen_RequestAlreadyPaid() external whenRequestNotNull whenRequestNotExpired {
        // Set the one-off USDT transfer payment request as current one
        uint256 paymentRequestId = 1;

        // Make Bob the payer for the default paymentRequest
        vm.startPrank({ msgSender: users.bob });

        // Approve the {PaymentModule} to transfer the ERC-20 token on Bob's behalf
        usdt.approve({ spender: address(paymentModule), amount: paymentRequests[paymentRequestId].config.amount });

        // Pay first the payment request
        paymentModule.payRequest({ requestId: paymentRequestId });

        // Expect the call to be reverted with the {RequestPaid} error
        vm.expectRevert(Errors.RequestPaid.selector);

        // Run the test
        paymentModule.payRequest({ requestId: paymentRequestId });
    }

    function test_RevertWhen_RequestCanceled()
        external
        whenRequestNotNull
        whenRequestNotExpired
        whenRequestNotAlreadyPaid
    {
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

    function test_RevertWhen_PaymentMethodTransfer_PaymentAmountLessThanRequestedAmount()
        external
        whenRequestNotNull
        whenRequestNotExpired
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodTransfer
        givenPaymentAmountInNativeToken
    {
        // Set the one-off ETH transfer payment request as current one
        uint256 paymentRequestId = 2;

        // Make Bob the payer for the default paymentRequest
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to be reverted with the {PaymentAmountLessThanRequestedAmount} error
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.PaymentAmountLessThanRequestedAmount.selector, paymentRequests[paymentRequestId].config.amount
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
        whenRequestNotExpired
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodTransfer
        givenPaymentAmountInNativeToken
        whenPaymentAmountEqualToPaymentValue
    {
        // Create a mock payment request with a one-off ETH transfer from the Eve's space
        Types.PaymentRequest memory paymentRequest = createPaymentRequestWithOneOffTransfer({
            asset: Constants.NATIVE_TOKEN,
            recipient: address(mockBadReceiver)
        });
        executeCreatePaymentRequest({ paymentRequest: paymentRequest, user: users.eve });

        // Retrieve the payment request ID
        uint256 paymentRequestId = _nextRequestId;

        // Make Bob the payer for this payment request
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to be reverted with the {NativeTokenPaymentFailed} error due to the bad receiver
        vm.expectRevert(Errors.NativeTokenPaymentFailed.selector);

        // Run the test
        paymentModule.payRequest{ value: paymentRequest.config.amount }({ requestId: paymentRequestId });
    }

    function test_PayRequest_PaymentMethodTransfer_NativeToken_OneOff()
        external
        whenRequestNotNull
        whenRequestNotExpired
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodTransfer
        givenPaymentAmountInNativeToken
        whenPaymentAmountEqualToPaymentValue
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
        emit IPaymentModule.RequestPaid({
            requestId: paymentRequestId,
            payer: users.bob,
            config: Types.Config({
                canExpire: paymentRequests[paymentRequestId].config.canExpire,
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
        whenRequestNotExpired
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodTransfer
        givenPaymentAmountInERC20Tokens
        whenPaymentAmountEqualToPaymentValue
    {
        // Set the recurring USDT transfer payment request as current one
        uint256 paymentRequestId = 3;

        // Make Bob the payer for the default paymentRequest
        vm.startPrank({ msgSender: users.bob });

        // Store the USDT balances of Bob and recipient before paying the payment request
        uint256 balanceOfBobBefore = usdt.balanceOf(users.bob);
        uint256 balanceOfRecipientBefore = usdt.balanceOf(address(space));

        // Approve the {PaymentModule} to transfer the ERC-20 tokens on Bob's behalf
        usdt.approve({ spender: address(paymentModule), amount: paymentRequests[paymentRequestId].config.amount });

        // Expect the {RequestPaid} event to be emitted
        vm.expectEmit();
        emit IPaymentModule.RequestPaid({
            requestId: paymentRequestId,
            payer: users.bob,
            config: Types.Config({
                canExpire: paymentRequests[paymentRequestId].config.canExpire,
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

        assertEq(uint8(paymentRequestStatus), uint8(Types.Status.Ongoing));
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
        whenRequestNotExpired
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodLinearStream
        givenPaymentAmountInERC20Tokens
        whenPaymentAmountEqualToPaymentValue
    {
        // Set the linear USDT stream-based paymentRequest as current one
        uint256 paymentRequestId = 4;

        // Make Bob the payer for the default paymentRequest
        vm.startPrank({ msgSender: users.bob });

        // Approve the {PaymentModule} to transfer the ERC-20 tokens on Bob's behalf
        usdt.approve({ spender: address(paymentModule), amount: paymentRequests[paymentRequestId].config.amount });

        // Expect the {RequestPaid} event to be emitted
        vm.expectEmit();
        emit IPaymentModule.RequestPaid({
            requestId: paymentRequestId,
            payer: users.bob,
            config: Types.Config({
                canExpire: paymentRequests[paymentRequestId].config.canExpire,
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

        assertEq(uint8(paymentRequestStatus), uint8(Types.Status.Ongoing));
        assertEq(paymentRequest.config.streamId, 1);
        assertEq(paymentRequest.config.paymentsLeft, 0);

        // Assert the actual and the expected state of the Sablier Lockup linear stream
        assertEq(paymentModule.getSender(1), address(paymentModule));
        assertEq(paymentModule.getRecipient(1), address(space));
        assertEq(address(paymentModule.getUnderlyingToken(1)), address(usdt));
        assertEq(paymentModule.getStartTime(1), paymentRequest.startTime);
        assertEq(paymentModule.getEndTime(1), paymentRequest.endTime);
    }

    function test_PayRequest_PaymentMethodTranchedStream()
        external
        whenRequestNotNull
        whenRequestNotExpired
        whenRequestNotAlreadyPaid
        whenRequestNotCanceled
        givenPaymentMethodTranchedStream
        givenPaymentAmountInERC20Tokens
        whenPaymentAmountEqualToPaymentValue
    {
        // Set the tranched USDT stream-based payment request as current one
        uint256 paymentRequestId = 5;

        // Cache the according payment request for this test suite
        Types.PaymentRequest memory paymentRequest = paymentRequests[paymentRequestId];

        // Make Bob the payer for the default payment request
        vm.startPrank({ msgSender: users.bob });

        // Approve the {PaymentModule} to transfer the ERC-20 tokens on Bob's behalf
        usdt.approve({ spender: address(paymentModule), amount: paymentRequest.config.amount });

        // Calculate the total number of tranches
        uint128 totalTranches = Helpers.computeNumberOfRecurringPayments(
            paymentRequest.config.recurrence, paymentRequest.endTime - paymentRequest.startTime
        );

        // Create the tranches array
        LockupTranched.Tranche[] memory tranches = new LockupTranched.Tranche[](totalTranches);

        // Populate tranches array
        uint40 trancheTimestamp = paymentRequest.startTime;
        uint40 durationPerTranche = Helpers._getDurationPerTrache(paymentRequest.config.recurrence);
        uint128 estimatedDepositAmount;
        uint128 amountPerTranche = paymentRequest.config.amount / totalTranches;
        for (uint256 i = 0; i < totalTranches; ++i) {
            trancheTimestamp += durationPerTranche;
            tranches[i] = (LockupTranched.Tranche({ amount: amountPerTranche, timestamp: trancheTimestamp }));
            estimatedDepositAmount += amountPerTranche;
        }

        // Account for rounding errors by adjusting the last tranche
        tranches[totalTranches - 1].amount += paymentRequest.config.amount - estimatedDepositAmount;

        // Create the common parameters for the Lockup.CreateEvent
        Lockup.CreateEventCommon memory commonParams = Lockup.CreateEventCommon({
            funder: address(paymentModule),
            sender: address(paymentModule),
            recipient: address(space),
            amounts: Lockup.CreateAmounts({ deposit: paymentRequest.config.amount, brokerFee: 0 }),
            token: IERC20(address(usdt)),
            cancelable: true,
            transferable: false,
            timestamps: Lockup.Timestamps({ start: paymentRequest.startTime, end: paymentRequest.endTime }),
            shape: "",
            broker: address(users.admin)
        });

        // Expect the {CreateLockupTranchedStream} and {RequestPaid} events to be emitted
        vm.expectEmit();

        // Emit the {CreateLockupTranchedStream} event
        emit ISablierLockup.CreateLockupTranchedStream({ streamId: 1, commonParams: commonParams, tranches: tranches });

        // Emit the {RequestPaid} event
        emit IPaymentModule.RequestPaid({
            requestId: paymentRequestId,
            payer: users.bob,
            config: Types.Config({
                canExpire: paymentRequests[paymentRequestId].config.canExpire,
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
        Types.PaymentRequest memory actualPaymentRequest = paymentModule.getRequest({ requestId: paymentRequestId });
        Types.Status actualPaymentRequestStatus = paymentModule.statusOf({ requestId: paymentRequestId });

        assertEq(uint8(actualPaymentRequestStatus), uint8(Types.Status.Ongoing));
        assertEq(actualPaymentRequest.config.streamId, 1);
        assertEq(actualPaymentRequest.config.paymentsLeft, 0);

        // Assert the actual and the expected state of the Sablier Lockup tranched stream
        assertEq(paymentModule.getSender(1), address(paymentModule));
        assertEq(paymentModule.getRecipient(1), address(space));
        assertEq(address(paymentModule.getUnderlyingToken(1)), address(usdt));
        assertEq(paymentModule.getStartTime(1), paymentRequest.startTime);
        assertEq(paymentModule.getEndTime(1), paymentRequest.endTime);
    }
}
