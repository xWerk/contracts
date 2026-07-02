// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SubscriptionModule_Unit_Concrete_Test } from "../SubscriptionModule.t.sol";
import { Constants } from "test/utils/Constants.sol";
import { Types } from "src/modules/subscription-module/libraries/Types.sol";

contract statusOf_Unit_Concrete_Test is SubscriptionModule_Unit_Concrete_Test {
    function setUp() public override {
        SubscriptionModule_Unit_Concrete_Test.setUp();
    }

    function test_StatusOf_Null() external view {
        // A never-registered subscription is {Null}
        assertEq(uint8(subscriptionModule.statusOf(MOCK_SUBSCRIPTION_ID)), uint8(Types.Status.Null));
    }

    function test_StatusOf_Revoked() external givenSubscribed {
        // Revoke the subscription through Eve's Space
        vm.prank({ msgSender: users.eve });
        space.execute({
            module: address(subscriptionModule),
            value: 0,
            data: abi.encodeWithSignature("revoke(bytes32)", MOCK_SUBSCRIPTION_ID)
        });

        // A revoked subscription is {Revoked} regardless of timing
        assertEq(uint8(subscriptionModule.statusOf(MOCK_SUBSCRIPTION_ID)), uint8(Types.Status.Revoked));
    }

    function test_StatusOf_Expired() external givenSubscribed {
        // Charge every cycle: warp to each cycle's start and charge it
        for (uint256 cycle = 0; cycle < Constants.SUBSCRIPTION_PERIODS; ++cycle) {
            vm.warp({ newTimestamp: _cycleStart(cycle) });
            subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID });
        }

        // Once all `periods` cycles have been charged, the subscription is {Expired}
        assertEq(uint8(subscriptionModule.statusOf(MOCK_SUBSCRIPTION_ID)), uint8(Types.Status.Expired));
    }

    function test_StatusOf_Expired_CatchUp() external givenSubscribed {
        // Warp past the whole billing window so every cycle is due, then charge them all back-to-back
        vm.warp({ newTimestamp: _cycleStart(Constants.SUBSCRIPTION_PERIODS - 1) });
        for (uint256 i = 0; i < Constants.SUBSCRIPTION_PERIODS; ++i) {
            subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID });
        }

        // Expiry is driven by the charged count reaching `periods`, even when charged as a catch-up
        assertEq(subscriptionModule.getSubscription(MOCK_SUBSCRIPTION_ID).chargedCount, Constants.SUBSCRIPTION_PERIODS);
        assertEq(uint8(subscriptionModule.statusOf(MOCK_SUBSCRIPTION_ID)), uint8(Types.Status.Expired));
    }

    function test_StatusOf_PastDue() external givenSubscribed {
        // Cycle 0 is due at `start` but has not been charged: the subscription is {PastDue}
        assertEq(uint8(subscriptionModule.statusOf(MOCK_SUBSCRIPTION_ID)), uint8(Types.Status.PastDue));

        // Charge cycle 0, then warp into cycle 1's window without charging it: {PastDue} again
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID });
        vm.warp({ newTimestamp: _cycleStart(1) });
        assertEq(uint8(subscriptionModule.statusOf(MOCK_SUBSCRIPTION_ID)), uint8(Types.Status.PastDue));

        // Warp beyond the whole billing window: the started-cycle count would exceed `periods` and is
        // capped at `periods`. With cycles still uncharged it must remain {PastDue}
        vm.warp({
            newTimestamp: _cycleStart(Constants.SUBSCRIPTION_PERIODS) + uint256(Constants.SUBSCRIPTION_INTERVAL)
        });
        assertEq(uint8(subscriptionModule.statusOf(MOCK_SUBSCRIPTION_ID)), uint8(Types.Status.PastDue));
    }

    function test_StatusOf_Active() external givenSubscribed {
        // Charge cycle 0 at `start`: the charged count now keeps pace with the started cycles
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID });

        // While still inside cycle 0's window, the subscription is {Active}
        assertEq(uint8(subscriptionModule.statusOf(MOCK_SUBSCRIPTION_ID)), uint8(Types.Status.Active));
    }

    /// @dev Returns the timestamp at which `cycle` becomes chargeable for the default mock subscription
    function _cycleStart(uint256 cycle) internal view returns (uint256) {
        Types.Subscription memory subscription = subscriptionModule.getSubscription(MOCK_SUBSCRIPTION_ID);
        return uint256(subscription.start) + cycle * uint256(subscription.interval);
    }
}
