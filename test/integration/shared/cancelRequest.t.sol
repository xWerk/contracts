// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Integration_Test } from "../Integration.t.sol";
import { PayRequest_Integration_Shared_Test } from "./payRequest.t.sol";

abstract contract CancelRequest_Integration_Shared_Test is Integration_Test, PayRequest_Integration_Shared_Test {
    function setUp() public virtual override(Integration_Test, PayRequest_Integration_Shared_Test) {
        PayRequest_Integration_Shared_Test.setUp();
    }

    modifier whenRequestSenderRecipient() {
        _;
    }

    modifier givenRequestStatusPending() {
        _;
    }

    modifier whenSenderInitialStreamSender() {
        _;
    }

    modifier whenRequestAlreadyCanceled() {
        _;
    }

    modifier givenRequestStatusAccepted() {
        _;
    }
}
