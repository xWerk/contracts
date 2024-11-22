// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Integration_Test } from "../../Integration.t.sol";
import { UD60x18 } from "@prb/math/src/UD60x18.sol";

contract Constructor_StreamManager_Integration_Concret_Test is Integration_Test {
    function setUp() public virtual override {
        Integration_Test.setUp();
    }

    function test_Constructor() external view {
        assertEq(UD60x18.unwrap(paymentModule.broker().fee), 0);
        assertEq(paymentModule.broker().account, users.admin);
        assertEq(address(paymentModule.LOCKUP_TRANCHED()), address(sablierV2LockupTranched));
        assertEq(address(paymentModule.LOCKUP_LINEAR()), address(sablierV2LockupLinear));
    }
}
