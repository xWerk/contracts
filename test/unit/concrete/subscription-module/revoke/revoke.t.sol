// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SubscriptionModule_Unit_Concrete_Test } from "../SubscriptionModule.t.sol";
import { Constants } from "test/utils/Constants.sol";
import { Errors } from "src/modules/subscription-module/libraries/Errors.sol";
import { ISubscriptionModule } from "src/modules/subscription-module/interfaces/ISubscriptionModule.sol";
import { Types } from "src/modules/subscription-module/libraries/Types.sol";

contract revoke_Unit_Concrete_Test is SubscriptionModule_Unit_Concrete_Test {
    function setUp() public override {
        SubscriptionModule_Unit_Concrete_Test.setUp();
    }

    function test_RevertWhen_SubscriptionNull() external {
        // Make Eve the caller
        vm.prank({ msgSender: users.eve });

        // Expect the next call to revert with the {SubscriptionNull} error
        vm.expectRevert(Errors.SubscriptionNull.selector);

        // Run the test: revoke a `subscriptionId` that was never registered
        space.execute({
            module: address(subscriptionModule),
            value: 0,
            data: abi.encodeWithSignature("revoke(bytes32)", MOCK_SUBSCRIPTION_ID)
        });
    }

    function test_RevertWhen_SubscriptionAlreadyRevoked() external givenSubscribed {
        // Revoke the subscription through Eve's Space
        vm.prank({ msgSender: users.eve });
        space.execute({
            module: address(subscriptionModule),
            value: 0,
            data: abi.encodeWithSignature("revoke(bytes32)", MOCK_SUBSCRIPTION_ID)
        });

        // Make Eve the caller again
        vm.prank({ msgSender: users.eve });

        // Expect the next call to revert with the {SubscriptionRevoked} error
        vm.expectRevert(Errors.SubscriptionRevoked.selector);

        // Run the test: attempt to revoke the same subscription a second time
        space.execute({
            module: address(subscriptionModule),
            value: 0,
            data: abi.encodeWithSignature("revoke(bytes32)", MOCK_SUBSCRIPTION_ID)
        });
    }

    function test_RevertWhen_CallerNotSubscriptionSpace() external givenSubscribed {
        // Make Bob the direct caller: `msg.sender` (Bob) != the subscription's {Space} (Eve's Space)
        vm.prank({ msgSender: users.bob });

        // Expect the next call to revert with the {OnlySubscriptionSpace} error
        vm.expectRevert(Errors.OnlySubscriptionSpace.selector);

        // Run the test
        subscriptionModule.revoke(MOCK_SUBSCRIPTION_ID);
    }

    function test_Revoke() external givenSubscribed {
        // Make Eve the caller
        vm.prank({ msgSender: users.eve });

        // Expect the {Revoked} event to be emitted for Eve's Space
        vm.expectEmit(address(subscriptionModule));
        emit ISubscriptionModule.Revoked({ space: address(space), subscriptionId: MOCK_SUBSCRIPTION_ID });

        // Run the test
        space.execute({
            module: address(subscriptionModule),
            value: 0,
            data: abi.encodeWithSignature("revoke(bytes32)", MOCK_SUBSCRIPTION_ID)
        });

        // Assert the subscription was marked as revoked
        Types.Subscription memory subscription = subscriptionModule.getSubscription(MOCK_SUBSCRIPTION_ID);
        assertTrue(subscription.isRevoked);
        assertEq(uint8(subscriptionModule.statusOf(MOCK_SUBSCRIPTION_ID)), uint8(Types.Status.Revoked));

        // Assert any further charge is now prevented
        vm.expectRevert(Errors.SubscriptionRevoked.selector);
        _charge(Constants.SUBSCRIPTION_AMOUNT);
    }
}
