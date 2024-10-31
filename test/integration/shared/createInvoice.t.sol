// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Integration_Test } from "../Integration.t.sol";
import { Types } from "./../../../src/modules/invoice-module/libraries/Types.sol";
import { Container } from "./../../../src/Container.sol";
import { MockBadContainer } from "../../mocks/MockBadContainer.sol";

abstract contract CreateInvoice_Integration_Shared_Test is Integration_Test {
    mapping(uint256 invoiceId => Types.Invoice) invoices;
    uint256 public _nextInvoiceId;

    function setUp() public virtual override {
        Integration_Test.setUp();
    }

    function createMockInvoices() internal {
        // Create a mock invoice with a one-off USDT transfer
        Types.Invoice memory invoice = createInvoiceWithOneOffTransfer({ asset: address(usdt) });
        invoices[1] = invoice;
        executeCreateInvoice({ invoice: invoice, user: users.eve });

        // Create a mock invoice with a one-off ETH transfer
        invoice = createInvoiceWithOneOffTransfer({ asset: address(0) });
        invoices[2] = invoice;
        executeCreateInvoice({ invoice: invoice, user: users.eve });

        // Create a mock invoice with a recurring USDT transfer
        invoice = createInvoiceWithRecurringTransfer({ recurrence: Types.Recurrence.Weekly });
        invoices[3] = invoice;
        executeCreateInvoice({ invoice: invoice, user: users.eve });

        // Create a mock invoice with a linear stream payment
        invoice = createInvoiceWithLinearStream();
        invoices[4] = invoice;
        executeCreateInvoice({ invoice: invoice, user: users.eve });

        // Create a mock invoice with a tranched stream payment
        invoice = createInvoiceWithTranchedStream({ recurrence: Types.Recurrence.Weekly });
        invoices[5] = invoice;
        executeCreateInvoice({ invoice: invoice, user: users.eve });

        _nextInvoiceId = 6;
    }

    modifier whenCallerContract() {
        _;
    }

    modifier whenCompliantContainer() {
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

    modifier givenPaymentMethodRecurringTransfer() {
        _;
    }

    modifier givenPaymentMethodTranchedStream() {
        _;
    }

    modifier givenPaymentMethodLinearStream() {
        _;
    }

    /// @dev Creates an invoice with a one-off transfer payment
    function createInvoiceWithOneOffTransfer(address asset) internal view returns (Types.Invoice memory invoice) {
        invoice = _createInvoice(uint40(block.timestamp), uint40(block.timestamp) + 4 weeks);

        invoice.payment = Types.Payment({
            method: Types.Method.Transfer,
            recurrence: Types.Recurrence.OneOff,
            paymentsLeft: 1,
            asset: asset,
            amount: 100e18,
            streamId: 0
        });
    }

    /// @dev Creates an invoice with a recurring transfer payment
    function createInvoiceWithRecurringTransfer(Types.Recurrence recurrence)
        internal
        view
        returns (Types.Invoice memory invoice)
    {
        invoice = _createInvoice(uint40(block.timestamp), uint40(block.timestamp) + 4 weeks);

        invoice.payment = Types.Payment({
            method: Types.Method.Transfer,
            recurrence: recurrence,
            paymentsLeft: 0,
            asset: address(usdt),
            amount: 100e18,
            streamId: 0
        });
    }

    /// @dev Creates an invoice with a linear stream-based payment
    function createInvoiceWithLinearStream() internal view returns (Types.Invoice memory invoice) {
        invoice = _createInvoice(uint40(block.timestamp), uint40(block.timestamp) + 4 weeks);

        invoice.payment = Types.Payment({
            method: Types.Method.LinearStream,
            recurrence: Types.Recurrence.Weekly, // doesn't matter
            paymentsLeft: 0,
            asset: address(usdt),
            amount: 100e18,
            streamId: 0
        });
    }

    /// @dev Creates an invoice with a tranched stream-based payment
    function createInvoiceWithTranchedStream(Types.Recurrence recurrence)
        internal
        view
        returns (Types.Invoice memory invoice)
    {
        invoice = _createInvoice(uint40(block.timestamp), uint40(block.timestamp) + 4 weeks);

        invoice.payment = Types.Payment({
            method: Types.Method.TranchedStream,
            recurrence: recurrence,
            paymentsLeft: 0,
            asset: address(usdt),
            amount: 100e18,
            streamId: 0
        });
    }

    /// @dev Creates an invoice with fuzzed parameters
    function createFuzzedInvoice(
        Types.Method method,
        Types.Recurrence recurrence,
        uint40 startTime,
        uint40 endTime,
        uint128 amount
    ) internal view returns (Types.Invoice memory invoice) {
        invoice = _createInvoice(startTime, endTime);

        invoice.payment = Types.Payment({
            method: method,
            recurrence: recurrence,
            paymentsLeft: 0,
            asset: address(usdt),
            amount: amount,
            streamId: 0
        });
    }

    function executeCreateInvoice(Types.Invoice memory invoice, address user) public {
        // Make the `user` account the caller who must be the owner of the {Container} contract
        vm.startPrank({ msgSender: user });

        // Create the invoice
        bytes memory data = abi.encodeWithSignature(
            "createInvoice((uint8,uint40,uint40,(uint8,uint8,uint40,address,uint128,uint256)))", invoice
        );

        // Select the according {Container} of the user

        if (user == users.eve) {
            Container(container).execute({ module: address(invoiceModule), value: 0, data: data });
        } else {
            MockBadContainer(badContainer).execute({ module: address(invoiceModule), value: 0, data: data });
        }

        // Stop the active prank
        vm.stopPrank();
    }

    function _createInvoice(uint40 startTime, uint40 endTime) internal pure returns (Types.Invoice memory invoice) {
        invoice.status = Types.Status.Pending;
        invoice.startTime = startTime;
        invoice.endTime = endTime;
    }
}
