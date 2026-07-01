// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SubscriptionModule_Unit_Concrete_Test } from "../SubscriptionModule.t.sol";
import { Constants } from "test/utils/Constants.sol";
import { Errors } from "src/modules/subscription-module/libraries/Errors.sol";
import { ISubscriptionModule } from "src/modules/subscription-module/interfaces/ISubscriptionModule.sol";
import { Types } from "src/modules/subscription-module/libraries/Types.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract charge_Unit_Concrete_Test is SubscriptionModule_Unit_Concrete_Test {
    function setUp() public override {
        SubscriptionModule_Unit_Concrete_Test.setUp();
    }

    function test_RevertWhen_SubscriptionNotRegistered() external {
        // Expect the next call to revert with the {SubscriptionNotActive} error
        vm.expectRevert(Errors.SubscriptionNotActive.selector);

        // Run the test: charge a `subscriptionId` that was never registered
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID, cycle: 0 });
    }

    function test_RevertWhen_SubscriptionRevoked() external givenSubscribed {
        // Revoke the subscription through Eve's Space
        vm.prank({ msgSender: users.eve });
        space.execute({
            module: address(subscriptionModule),
            value: 0,
            data: abi.encodeWithSignature("revoke(bytes32)", MOCK_SUBSCRIPTION_ID)
        });

        // Expect the next call to revert with the {SubscriptionRevoked} error
        vm.expectRevert(Errors.SubscriptionRevoked.selector);

        // Run the test
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID, cycle: 0 });
    }

    function test_RevertWhen_CycleAlreadyCharged() external givenSubscribed {
        // Charge cycle 0 successfully (it is due at `start`)
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID, cycle: 0 });

        // Expect the next call to revert with the {CycleAlreadyCharged} error
        vm.expectRevert(Errors.CycleAlreadyCharged.selector);

        // Run the test: attempt to charge the same cycle again
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID, cycle: 0 });
    }

    function test_RevertWhen_CycleOutOfBounds() external givenSubscribed {
        // Warp far enough into the future so the out-of-bounds cycle would otherwise be due
        vm.warp({
            newTimestamp: block.timestamp + uint256(Constants.SUBSCRIPTION_PERIODS) * Constants.SUBSCRIPTION_INTERVAL
        });

        // Expect the next call to revert with the {CycleOutOfBounds} error
        vm.expectRevert(Errors.CycleOutOfBounds.selector);

        // Run the test
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID, cycle: Constants.SUBSCRIPTION_PERIODS });
    }

    function test_RevertWhen_CycleNotDue() external givenSubscribed {
        // Expect the next call to revert with the {CycleNotDue} error
        vm.expectRevert(Errors.CycleNotDue.selector);

        // Run the test: cycle 1 only becomes due one interval after `start`, but no time has passed
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID, cycle: 1 });
    }

    function test_RevertWhen_SpaceHasNotApprovedModule() external {
        // Register the subscription without approving the module
        Types.SubscribeInput memory input = _defaultInput();
        bytes memory signature = _signInput(input);

        // Subscribe through Eve's Space without granting any allowance to the module
        vm.prank({ msgSender: users.eve });
        space.execute({ module: address(subscriptionModule), value: 0, data: _subscribeData(input, signature) });

        // Expect the next call to revert (the token's `safeTransferFrom` fails on missing allowance)
        vm.expectRevert();

        // Run the test
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID, cycle: 0 });
    }

    function test_Charge() external givenSubscribed {
        // Snapshot the balances before the charge
        uint256 spaceBalanceBefore = IERC20(address(usdt)).balanceOf(address(space));
        uint256 treasuryBalanceBefore = IERC20(address(usdt)).balanceOf(werkTreasury);

        // The subscription starts at the current timestamp, so cycle 0's `paidUntil` is one interval later
        uint40 expectedPaidUntil = uint40(block.timestamp) + Constants.SUBSCRIPTION_INTERVAL;

        // Expect the {SubscriptionCharged} event to be emitted with the pinned amount and computed `paidUntil`
        vm.expectEmit(address(subscriptionModule));
        emit ISubscriptionModule.SubscriptionCharged({
            space: address(space),
            subscriptionId: MOCK_SUBSCRIPTION_ID,
            cycle: 0,
            amount: Constants.SUBSCRIPTION_AMOUNT,
            paidUntil: expectedPaidUntil
        });

        // Run the test as the relayer (Bob) to prove the charge is permissionless
        vm.prank({ msgSender: users.bob });
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID, cycle: 0 });

        // Assert the cycle was marked as charged
        assertTrue(subscriptionModule.isCharged(MOCK_SUBSCRIPTION_ID, 0));

        // Assert the charged-cycle counter was bumped
        assertEq(subscriptionModule.getSubscription(MOCK_SUBSCRIPTION_ID).chargedCount, 1);

        // Assert the pinned amount moved from the {Space} to the treasury
        assertEq(IERC20(address(usdt)).balanceOf(address(space)), spaceBalanceBefore - Constants.SUBSCRIPTION_AMOUNT);
        assertEq(IERC20(address(usdt)).balanceOf(werkTreasury), treasuryBalanceBefore + Constants.SUBSCRIPTION_AMOUNT);
    }

    function test_Charge_OutOfOrder() external givenSubscribed {
        // Warp into cycle 2's window so both cycle 0 and cycle 2 are due
        vm.warp({ newTimestamp: uint256(block.timestamp) + 2 * uint256(Constants.SUBSCRIPTION_INTERVAL) });

        // Charge cycle 2 before cycle 0 to exetestrcise out-of-order charging
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID, cycle: 2 });

        // Assert only cycle 2 is flagged, the counter reflects one charge, and status is still {PastDue}
        // (cycles 0 and 1 remain due and uncharged), NOT {Expired}
        assertTrue(subscriptionModule.isCharged(MOCK_SUBSCRIPTION_ID, 2));
        assertFalse(subscriptionModule.isCharged(MOCK_SUBSCRIPTION_ID, 0));
        assertEq(subscriptionModule.getSubscription(MOCK_SUBSCRIPTION_ID).chargedCount, 1);
        assertEq(uint8(subscriptionModule.statusOf(MOCK_SUBSCRIPTION_ID)), uint8(Types.Status.PastDue));

        // Charge the skipped earlier cycle and assert the counter keeps counting regardless of order
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID, cycle: 0 });
        assertEq(subscriptionModule.getSubscription(MOCK_SUBSCRIPTION_ID).chargedCount, 2);
    }
}
