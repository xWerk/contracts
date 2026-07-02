// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SubscriptionModule_Unit_Concrete_Test } from "../SubscriptionModule.t.sol";
import { Constants } from "test/utils/Constants.sol";
import { Errors } from "src/modules/subscription-module/libraries/Errors.sol";
import { ISubscriptionModule } from "src/modules/subscription-module/interfaces/ISubscriptionModule.sol";
import { Types } from "src/modules/subscription-module/libraries/Types.sol";

contract subscribe_Unit_Concrete_Test is SubscriptionModule_Unit_Concrete_Test {
    function setUp() public override {
        SubscriptionModule_Unit_Concrete_Test.setUp();
    }

    function test_RevertWhen_CallerNotSubscriptionSpace() external {
        // Build a valid signed input for Eve's Space
        Types.SubscribeInput memory input = _defaultInput();
        bytes memory signature = _signInput(input);

        // Make Bob the direct caller: `msg.sender` (Bob) != `input.space` (Eve's Space)
        vm.prank({ msgSender: users.bob });

        // Expect the next call to revert with the {OnlySubscriptionSpace} error
        vm.expectRevert(Errors.OnlySubscriptionSpace.selector);

        // Run the test
        subscriptionModule.subscribe(input, signature);
    }

    function test_RevertWhen_SignatureExpired() external whenCallerSpace {
        // Build a valid signed input, then warp past its `validUntil` expiry
        Types.SubscribeInput memory input = _defaultInput();
        bytes memory signature = _signInput(input);
        vm.warp(input.validUntil + 1);

        // Expect the next call to revert with the {SignatureExpired} error
        vm.expectRevert(Errors.SignatureExpired.selector);

        // Run the test
        space.execute({ module: address(subscriptionModule), value: 0, data: _subscribeData(input, signature) });
    }

    function test_RevertWhen_InvalidBackendSignature() external whenCallerSpace {
        Types.SubscribeInput memory input = _defaultInput();

        // Sign the exact terms with the correct signer, then alter the amount after signing
        bytes memory signature = _signInput(input);
        input.amount = Constants.SUBSCRIPTION_AMOUNT + 1;

        // Expect the next call to revert with the {InvalidBackendSignature} error
        vm.expectRevert(Errors.InvalidBackendSignature.selector);

        // Run the test
        space.execute({ module: address(subscriptionModule), value: 0, data: _subscribeData(input, signature) });
    }

    function test_RevertWhen_SubscriptionAlreadyExists() external whenValidBackendSignature givenSubscribed {
        // The `givenSubscribed` modifier already registered the default subscription; a second attempt with the
        // same `subscriptionId` must revert
        Types.SubscribeInput memory input = _defaultInput();
        bytes memory signature = _signInput(input);

        // Make Eve the caller
        vm.prank({ msgSender: users.eve });

        // Expect the next call to revert with the {SubscriptionAlreadyExists} error
        vm.expectRevert(Errors.SubscriptionAlreadyExists.selector);

        // Run the test
        space.execute({ module: address(subscriptionModule), value: 0, data: _subscribeData(input, signature) });
    }

    function test_Subscribe() external whenCallerSpace whenValidBackendSignature givenSubscriptionNotRegistered {
        Types.SubscribeInput memory input = _defaultInput();
        bytes memory signature = _signInput(input);

        // The `start` is pinned to the current block timestamp
        uint40 expectedStart = uint40(block.timestamp);

        // Expect the {Subscribed} event to be emitted with the signed terms
        vm.expectEmit(address(subscriptionModule));
        emit ISubscriptionModule.Subscribed({
            space: address(space),
            subscriptionId: input.subscriptionId,
            tier: input.tier,
            asset: input.asset,
            amount: input.amount,
            interval: input.interval,
            periods: input.periods,
            start: expectedStart
        });

        // Run the test
        space.execute({ module: address(subscriptionModule), value: 0, data: _subscribeData(input, signature) });

        // Assert the subscription details were pinned on-chain
        Types.Subscription memory subscription = subscriptionModule.getSubscription(input.subscriptionId);
        assertEq(subscription.space, address(space));
        assertEq(subscription.interval, input.interval);
        assertEq(subscription.periods, input.periods);
        assertEq(subscription.start, expectedStart);
        assertEq(subscription.asset, input.asset);
        assertEq(subscription.tier, input.tier);
        assertFalse(subscription.isRevoked);
        assertEq(subscription.chargedCount, 0);
        assertEq(subscription.amount, input.amount);

        // Assert the derived status is PastDue right after subscribing: cycle 0 is due at `start` and has
        // not been charged yet
        assertEq(uint8(subscriptionModule.statusOf(input.subscriptionId)), uint8(Types.Status.PastDue));

        // Assert no cycle has been charged yet
        assertFalse(subscriptionModule.isCharged(input.subscriptionId, 0));
    }
}
