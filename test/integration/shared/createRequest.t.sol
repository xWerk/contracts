// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Integration_Test } from "../Integration.t.sol";
import { Types } from "./../../../src/modules/payment-module/libraries/Types.sol";
import { Space } from "./../../../src/Space.sol";
import { MockBadSpace } from "../../mocks/MockBadSpace.sol";
import { Constants } from "../../utils/Constants.sol";

abstract contract CreateRequest_Integration_Shared_Test is Integration_Test {
    mapping(uint256 paymentRequestId => Types.PaymentRequest) paymentRequests;
    uint256 public _nextRequestId;

    function setUp() public virtual override {
        Integration_Test.setUp();
    }

    function createMockPaymentRequests() internal {
        // Create a mock payment request with a one-off USDT transfer
        Types.PaymentRequest memory paymentRequest =
            createPaymentRequestWithOneOffTransfer({ asset: address(usdt), recipient: address(space) });
        paymentRequests[1] = paymentRequest;
        executeCreatePaymentRequest({ paymentRequest: paymentRequest, user: users.eve });

        // Create a mock payment request with a one-off ETH transfer
        paymentRequest =
            createPaymentRequestWithOneOffTransfer({ asset: Constants.NATIVE_TOKEN, recipient: address(space) });
        paymentRequests[2] = paymentRequest;
        executeCreatePaymentRequest({ paymentRequest: paymentRequest, user: users.eve });

        // Create a mock payment request with a recurring USDT transfer
        paymentRequest =
            createPaymentWithRecurringTransfer({ recurrence: Types.Recurrence.Weekly, recipient: address(space) });
        paymentRequests[3] = paymentRequest;
        executeCreatePaymentRequest({ paymentRequest: paymentRequest, user: users.eve });

        // Create a mock payment request with a linear stream payment
        paymentRequest = createPaymentRequestWithLinearStream({ recipient: address(space) });
        paymentRequests[4] = paymentRequest;
        executeCreatePaymentRequest({ paymentRequest: paymentRequest, user: users.eve });

        // Create a mock payment request with a tranched stream payment
        paymentRequest =
            createPaymentRequestWithTranchedStream({ recurrence: Types.Recurrence.Weekly, recipient: address(space) });
        paymentRequests[5] = paymentRequest;
        executeCreatePaymentRequest({ paymentRequest: paymentRequest, user: users.eve });

        // Create a mock payment request with an unlimited USDT transfer
        paymentRequest = createPaymentWithCustomNoOfTransfers({ asset: address(usdt), recipient: address(space) });
        paymentRequests[6] = paymentRequest;
        executeCreatePaymentRequest({ paymentRequest: paymentRequest, user: users.eve });

        _nextRequestId = 7;
    }

    modifier whenCompliantSpace() {
        _;
    }

    modifier whenNonZeroPaymentAmount() {
        _;
    }

    modifier whenStartTimeLowerThanEndTime() {
        _;
    }

    modifier whenEndTimeInTheFuture() {
        _;
    }

    modifier whenPaymentIntervalLongEnough() {
        _;
    }

    modifier whenTranchedStreamWithGoodRecurring() {
        _;
    }

    modifier whenPaymentAssetNotNativeToken() {
        _;
    }

    modifier givenPaymentMethodOneOffTransfer() {
        _;
    }

    modifier givenCustomPaymentRecurrence() {
        _;
    }

    modifier givenPaymentMethodRecurringTransfer() {
        _;
    }

    modifier givenPaymentMethodTranchedStream() {
        _;
    }

    modifier givenPaymentMethodLinearStream() {
        _;
    }

    function createPaymentWithCustomNoOfTransfers(
        address asset,
        address recipient
    )
        internal
        view
        returns (Types.PaymentRequest memory paymentRequest)
    {
        paymentRequest =
            _createBasePaymentRequest(recipient, uint40(block.timestamp), uint40(block.timestamp) + 999 weeks);

        paymentRequest.config = Types.Config({
            canExpire: true, // make the payment request expirable
            method: Types.Method.Transfer,
            recurrence: Types.Recurrence.Custom,
            paymentsLeft: 150, // set a custom number of payments
            asset: asset,
            amount: 100e6,
            streamId: 0
        });
    }

    /// @dev Creates a payment request with a one-off transfer payment
    function createPaymentRequestWithOneOffTransfer(
        address asset,
        address recipient
    )
        internal
        view
        returns (Types.PaymentRequest memory paymentRequest)
    {
        paymentRequest =
            _createBasePaymentRequest(recipient, uint40(block.timestamp), uint40(block.timestamp) + 4 weeks);

        paymentRequest.config = Types.Config({
            canExpire: false,
            method: Types.Method.Transfer,
            recurrence: Types.Recurrence.OneOff,
            paymentsLeft: 1,
            asset: asset,
            amount: 100e6,
            streamId: 0
        });
    }

    /// @dev Creates a payment request with a recurring transfer payment
    function createPaymentWithRecurringTransfer(
        Types.Recurrence recurrence,
        address recipient
    )
        internal
        view
        returns (Types.PaymentRequest memory paymentRequest)
    {
        paymentRequest =
            _createBasePaymentRequest(recipient, uint40(block.timestamp), uint40(block.timestamp) + 4 weeks);

        paymentRequest.config = Types.Config({
            canExpire: false,
            method: Types.Method.Transfer,
            recurrence: recurrence,
            paymentsLeft: 0,
            asset: address(usdt),
            amount: 100e6,
            streamId: 0
        });
    }

    /// @dev Creates a payment request with a linear stream-based payment
    function createPaymentRequestWithLinearStream(address recipient)
        internal
        view
        returns (Types.PaymentRequest memory paymentRequest)
    {
        paymentRequest =
            _createBasePaymentRequest(recipient, uint40(block.timestamp), uint40(block.timestamp) + 4 weeks);

        paymentRequest.config = Types.Config({
            canExpire: false,
            method: Types.Method.LinearStream,
            recurrence: Types.Recurrence.Weekly, // doesn't matter
            paymentsLeft: 0,
            asset: address(usdt),
            amount: 100e6,
            streamId: 0
        });
    }

    /// @dev Creates a payment request with a tranched stream-based payment
    function createPaymentRequestWithTranchedStream(
        Types.Recurrence recurrence,
        address recipient
    )
        internal
        view
        returns (Types.PaymentRequest memory paymentRequest)
    {
        paymentRequest =
            _createBasePaymentRequest(recipient, uint40(block.timestamp), uint40(block.timestamp) + 4 weeks);

        paymentRequest.config = Types.Config({
            canExpire: false,
            method: Types.Method.TranchedStream,
            recurrence: recurrence,
            paymentsLeft: 0,
            asset: address(usdt),
            amount: 100e6,
            streamId: 0
        });
    }

    function executeCreatePaymentRequest(Types.PaymentRequest memory paymentRequest, address user) public {
        // Make the `user` account the caller who must be the owner of the {Space} contract
        vm.startPrank({ msgSender: user });

        // Create the payment request
        bytes memory data = abi.encodeWithSignature(
            "createRequest((bool,bool,uint40,uint40,address,(bool,uint8,uint8,uint40,address,uint128,uint256)))",
            paymentRequest
        );

        // Select the according {Space} of the user
        if (user == users.eve) {
            Space(space).execute({ module: address(paymentModule), value: 0, data: data });
        } else {
            MockBadSpace(badSpace).execute({ module: address(paymentModule), value: 0, data: data });
        }

        // Stop the active prank
        vm.stopPrank();
    }

    function _createBasePaymentRequest(
        address recipient,
        uint40 startTime,
        uint40 endTime
    )
        internal
        pure
        returns (Types.PaymentRequest memory paymentRequest)
    {
        paymentRequest.recipient = recipient;
        paymentRequest.startTime = startTime;
        paymentRequest.endTime = endTime;
    }
}
