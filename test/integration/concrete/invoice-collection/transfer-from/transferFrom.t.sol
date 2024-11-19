// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Integration_Test } from "../../../Integration.t.sol";

contract TransferFrom_Integration_Concret_Test is Integration_Test {
    function setUp() public virtual override {
        Integration_Test.setUp();

        // Mint an invoice NFT to Bob
        vm.startPrank({ msgSender: users.admin });
        invoiceCollection.mintInvoice({
            invoiceURI: "ipfs://QmSomeHash",
            paymentRecipient: users.bob,
            paymentRequestId: "1"
        });
        vm.stopPrank();
    }

    function test_TransferFrom() external {
        // Expect the transfer to revert with the "Soulbound token!" reason
        vm.expectRevert("Soulbound token!");

        // Make Bob the caller as he's the owner of the invoice NFT
        vm.startPrank({ msgSender: users.bob });

        // Run the test
        invoiceCollection.transferFrom(users.bob, users.eve, 1);
    }
}
