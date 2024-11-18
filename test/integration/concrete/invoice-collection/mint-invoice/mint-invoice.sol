// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Integration_Test } from "../../../Integration.t.sol";
import { Errors } from "../../../../utils/Errors.sol";
import { Events } from "../../../../utils/Events.sol";

contract MintInvoice_Integration_Concret_Test is Integration_Test {
    function setUp() public virtual override {
        Integration_Test.setUp();
    }

    function test_RevertWhen_CallerNotRelayer() external {
        // Make Bob the caller in this test suite which is the authorized Relayer
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to revert with the {Unauthorized} error
        vm.expectRevert(Errors.Unauthorized.selector);

        // Run the test
        invoiceCollection.mintInvoice({
            invoiceURI: "ipfs://QmSomeHash",
            paymentRecipient: users.bob,
            paymentRequestId: "1"
        });
    }

    modifier whenCallerRelayer() {
        // Make Admin the caller for the next test suite as they're the authorized Relayer
        vm.startPrank({ msgSender: users.admin });

        _;
    }

    function test_MintInvoice() external whenCallerRelayer {
        // Expect the {MintInvoice} event to be emitted
        vm.expectEmit();
        emit Events.InvoiceMinted({ to: users.bob, tokenId: 1, paymentRequestId: "1" });

        // Run the test
        invoiceCollection.mintInvoice({
            invoiceURI: "ipfs://QmSomeHash",
            paymentRecipient: users.bob,
            paymentRequestId: "1"
        });

        // Assert the actual and expected payment request ID associated with the invoice NFT
        string memory actualPaymentRequestId = invoiceCollection.tokenIdToPaymentRequestId(1);
        assertEq(actualPaymentRequestId, "1");

        // Assert the actual and expected invoice URI associated with the invoice NFT
        string memory actualInvoiceURI = invoiceCollection.tokenURI(1);
        assertEq(actualInvoiceURI, "ipfs://QmSomeHash");

        // Assert the actual and expected owner of the invoice NFT
        assertEq(invoiceCollection.ownerOf(1), users.bob);
    }
}
