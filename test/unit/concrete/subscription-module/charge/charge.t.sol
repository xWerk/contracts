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

    function test_RevertWhen_SubscriptionNull() external {
        // Expect the next call to revert with the {SubscriptionNull} error
        vm.expectRevert(Errors.SubscriptionNull.selector);

        // Run the test: charge a `subscriptionId` that was never registered
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID });
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
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID });
    }

    function test_RevertWhen_SubscriptionEnded() external givenSubscribed {
        // Charge every cycle: warp to each cycle's start and charge it
        for (uint256 cycle = 0; cycle < Constants.SUBSCRIPTION_CYCLES; ++cycle) {
            vm.warp({ newTimestamp: _cycleStart(cycle) });
            subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID });
        }

        // Warp far beyond the whole billing window so time is not the limiting factor
        vm.warp({ newTimestamp: block.timestamp + uint256(Constants.SUBSCRIPTION_INTERVAL) });

        // Expect the next call to revert with the {SubscriptionEnded} error
        vm.expectRevert(Errors.SubscriptionEnded.selector);

        // Run the test: all `cycles` cycles have been charged
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID });
    }

    function test_RevertWhen_CycleNotDue() external givenSubscribed {
        // Charge cycle 0 successfully (it is due at `start`)
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID });

        // Expect the next call to revert with the {CycleNotDue} error
        vm.expectRevert(Errors.CycleNotDue.selector);

        // Run the test: this is the double-charge guard — the counter moved to cycle 1, which only becomes
        // due one interval after `start`, so an immediate repeated charge must revert
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID });
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
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID });
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
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID });

        // Assert the cycle was marked as charged
        assertTrue(subscriptionModule.isCharged(MOCK_SUBSCRIPTION_ID, 0));

        // Assert the charged-cycle counter was bumped
        assertEq(subscriptionModule.getSubscription(MOCK_SUBSCRIPTION_ID).cyclesCharged, 1);

        // Assert the pinned amount moved from the {Space} to the treasury
        assertEq(IERC20(address(usdt)).balanceOf(address(space)), spaceBalanceBefore - Constants.SUBSCRIPTION_AMOUNT);
        assertEq(IERC20(address(usdt)).balanceOf(werkTreasury), treasuryBalanceBefore + Constants.SUBSCRIPTION_AMOUNT);
    }

    function test_Charge_CatchUp() external givenSubscribed {
        // Warp into cycle 2's window so three cycles (0, 1 and 2) are due and unpaid
        vm.warp({ newTimestamp: uint256(block.timestamp) + 2 * uint256(Constants.SUBSCRIPTION_INTERVAL) });

        // Snapshot the treasury balance before catching up
        uint256 treasuryBalanceBefore = IERC20(address(usdt)).balanceOf(werkTreasury);

        // Charge the arrears: consecutive calls succeed while cycles remain overdue, in strict order
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID });
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID });
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID });

        // Assert cycles 0-2 are charged, the counter kept pace and exactly three payments were pulled
        assertTrue(subscriptionModule.isCharged(MOCK_SUBSCRIPTION_ID, 2));
        assertFalse(subscriptionModule.isCharged(MOCK_SUBSCRIPTION_ID, 3));
        assertEq(subscriptionModule.getSubscription(MOCK_SUBSCRIPTION_ID).cyclesCharged, 3);
        assertEq(
            IERC20(address(usdt)).balanceOf(werkTreasury),
            treasuryBalanceBefore + 3 * uint256(Constants.SUBSCRIPTION_AMOUNT)
        );

        // Assert the subscription is paid up ({Active}) and a fourth charge reverts: cycle 3 is not due yet
        assertEq(uint8(subscriptionModule.statusOf(MOCK_SUBSCRIPTION_ID)), uint8(Types.Status.Active));
        vm.expectRevert(Errors.CycleNotDue.selector);
        subscriptionModule.charge({ subscriptionId: MOCK_SUBSCRIPTION_ID });
    }

    /// @dev Returns the timestamp at which `cycle` becomes chargeable for the default mock subscription
    function _cycleStart(uint256 cycle) internal view returns (uint256) {
        Types.Subscription memory subscription = subscriptionModule.getSubscription(MOCK_SUBSCRIPTION_ID);
        return uint256(subscription.start) + cycle * uint256(subscription.interval);
    }
}
