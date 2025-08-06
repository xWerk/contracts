// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Integration_Test } from "../Integration.t.sol";
import { CreateRequest_Integration_Shared_Test } from "./createRequest.t.sol";

abstract contract PayRequest_Integration_Shared_Test is Integration_Test, CreateRequest_Integration_Shared_Test {
    function setUp() public virtual override(Integration_Test, CreateRequest_Integration_Shared_Test) {
        CreateRequest_Integration_Shared_Test.setUp();
        createMockPaymentRequests();
    }

    modifier whenRequestNotNull() {
        _;
    }

    modifier whenRequestNotExpired() {
        _;
    }

    modifier whenRequestNotAlreadyPaid() {
        _;
    }

    modifier whenRequestNotCanceled() {
        _;
    }

    modifier givenPaymentMethodTransfer() {
        _;
    }

    modifier givenPaymentAmountInNativeToken() {
        _;
    }

    modifier givenPaymentAmountInERC20Tokens() {
        _;
    }

    modifier whenPaymentAmountEqualToPaymentValue() {
        _;
    }

    modifier whenNativeTokenPaymentSucceeds() {
        _;
    }
}
