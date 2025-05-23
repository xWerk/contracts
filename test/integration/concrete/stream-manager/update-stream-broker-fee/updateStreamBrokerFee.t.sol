// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Types } from "src/modules/payment-module/libraries/Types.sol";
import { IStreamManager } from "src/modules/payment-module/sablier-lockup/interfaces/IStreamManager.sol";
import { ud, UD60x18 } from "@prb/math/src/UD60x18.sol";
import { Integration_Test } from "test/integration/Integration.t.sol";

contract UpdateStreamBrokerFee_Integration_Concret_Test is Integration_Test {
    Types.PaymentRequest paymentRequest;

    function setUp() public virtual override {
        Integration_Test.setUp();
    }

    function test_RevertWhen_CallerNotOwner() external {
        // Make Bob the caller in this test suite who is not the broker admin
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to revert with the {OwnableUnauthorizedAccount} error
        vm.expectRevert(
            abi.encodeWithSelector(bytes4(keccak256(bytes("OwnableUnauthorizedAccount(address)"))), users.bob)
        );

        // Run the test
        paymentModule.updateStreamBrokerFee({ newBrokerFee: ud(0.05e18) });
    }

    modifier whenCallerBrokerAdmin() {
        // Make Admin the caller in this test suite
        vm.startPrank({ msgSender: users.admin });

        _;
    }

    function test_UpdateStreamBrokerFee() external whenCallerBrokerAdmin {
        UD60x18 newBrokerFee = ud(0.05e18);

        // Expect the {BrokerFeeUpdated} to be emitted
        vm.expectEmit();
        emit IStreamManager.BrokerFeeUpdated({ oldFee: ud(0), newFee: newBrokerFee });

        // Run the test
        paymentModule.updateStreamBrokerFee(newBrokerFee);

        // Assert the actual and expected broker fee
        UD60x18 actualBrokerFee = paymentModule.broker().fee;
        assertEq(UD60x18.unwrap(actualBrokerFee), UD60x18.unwrap(newBrokerFee));
    }
}
