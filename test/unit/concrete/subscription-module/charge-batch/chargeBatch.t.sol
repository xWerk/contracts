// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SubscriptionModule_Unit_Concrete_Test } from "../SubscriptionModule.t.sol";
import { Constants } from "test/utils/Constants.sol";
import { Errors } from "src/modules/subscription-module/libraries/Errors.sol";
import { Types } from "src/modules/subscription-module/libraries/Types.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract chargeBatch_Unit_Concrete_Test is SubscriptionModule_Unit_Concrete_Test {
    function setUp() public override {
        SubscriptionModule_Unit_Concrete_Test.setUp();
    }

    function test_RevertWhen_CallerNotRelayer() external givenSubscribed {
        (bytes32[] memory ids, uint128[] memory amounts) = _singleItemBatch(Constants.SUBSCRIPTION_AMOUNT);

        // Make Bob the caller
        vm.prank({ msgSender: users.bob });

        // Expect the next call to revert with the {OnlyRelayer} error
        vm.expectRevert(Errors.OnlyRelayer.selector);

        // Run the test
        subscriptionModule.chargeBatch(ids, amounts);
    }

    function test_RevertWhen_ArrayLengthMismatch() external givenSubscribed {
        // Build mismatched arrays: two ids, one amount
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = MOCK_SUBSCRIPTION_ID;
        ids[1] = SECOND_SUBSCRIPTION_ID;
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = Constants.SUBSCRIPTION_AMOUNT;

        // Expect the next call to revert with the {ArrayLengthMismatch} error
        vm.expectRevert(Errors.ArrayLengthMismatch.selector);

        // Run the test
        vm.prank({ msgSender: subscriptionRelayer });
        subscriptionModule.chargeBatch(ids, amounts);
    }

    function test_ChargeBatch() external givenSubscribed whenArrayLengthMatch {
        // Register a second subscription for the same {Space}
        Types.SubscribeInput memory second = _defaultInput();
        second.subscriptionId = SECOND_SUBSCRIPTION_ID;
        _subscribe(second);

        // Save balances before
        uint256 spaceBalanceBefore = IERC20(address(usdt)).balanceOf(address(space));
        uint256 treasuryBalanceBefore = IERC20(address(usdt)).balanceOf(werkTreasury);

        // Batch-charge cycle 0 of both subscriptions, each with its own amount
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = MOCK_SUBSCRIPTION_ID;
        ids[1] = SECOND_SUBSCRIPTION_ID;
        uint128[] memory amounts = new uint128[](2);
        amounts[0] = Constants.SUBSCRIPTION_AMOUNT;
        amounts[1] = Constants.SUBSCRIPTION_AMOUNT * 2;

        // Run the test
        vm.prank({ msgSender: subscriptionRelayer });
        subscriptionModule.chargeBatch(ids, amounts);

        // Assert both subscriptions had cycle 0 charged
        assertTrue(subscriptionModule.isCharged(MOCK_SUBSCRIPTION_ID, 0));
        assertTrue(subscriptionModule.isCharged(SECOND_SUBSCRIPTION_ID, 0));
        assertEq(subscriptionModule.getSubscription(MOCK_SUBSCRIPTION_ID).cyclesCharged, 1);
        assertEq(subscriptionModule.getSubscription(SECOND_SUBSCRIPTION_ID).cyclesCharged, 1);

        // Assert the summed amounts moved from the {Space} to the treasury
        uint256 totalCharged = uint256(amounts[0]) + uint256(amounts[1]);
        assertEq(IERC20(address(usdt)).balanceOf(address(space)), spaceBalanceBefore - totalCharged);
        assertEq(IERC20(address(usdt)).balanceOf(werkTreasury), treasuryBalanceBefore + totalCharged);
    }

    function test_ChargeBatch_SkipsFailingItem() external givenSubscribed whenArrayLengthMatch {
        // Treasury balance before
        uint256 treasuryBalanceBefore = IERC20(address(usdt)).balanceOf(werkTreasury);

        // Batch a never-registered id (fails with {SubscriptionNull}) with the registered subscription
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = keccak256("werk.subscription.unregistered");
        ids[1] = MOCK_SUBSCRIPTION_ID;
        uint128[] memory amounts = new uint128[](2);
        amounts[0] = Constants.SUBSCRIPTION_AMOUNT;
        amounts[1] = Constants.SUBSCRIPTION_AMOUNT;

        // Run the test: the failing first item must not revert the batch
        vm.prank({ msgSender: subscriptionRelayer });
        subscriptionModule.chargeBatch(ids, amounts);

        // Assert the registered subscription was still charged
        assertTrue(subscriptionModule.isCharged(MOCK_SUBSCRIPTION_ID, 0));
        assertEq(
            IERC20(address(usdt)).balanceOf(werkTreasury),
            treasuryBalanceBefore + uint256(Constants.SUBSCRIPTION_AMOUNT)
        );
    }

    function test_ChargeBatch_SkippedItemStateUntouched() external givenSubscribed whenArrayLengthMatch {
        // Revoke the subscription through Eve's Space so its charge fails inside the batch
        vm.prank({ msgSender: users.eve });
        space.execute({
            module: address(subscriptionModule),
            value: 0,
            data: abi.encodeWithSignature("revoke(bytes32)", MOCK_SUBSCRIPTION_ID)
        });

        (bytes32[] memory ids, uint128[] memory amounts) = _singleItemBatch(Constants.SUBSCRIPTION_AMOUNT);

        // Run the test
        vm.prank({ msgSender: subscriptionRelayer });
        subscriptionModule.chargeBatch(ids, amounts);

        // Assert the skipped item's state is untouched: nothing was charged
        assertFalse(subscriptionModule.isCharged(MOCK_SUBSCRIPTION_ID, 0));
        assertEq(subscriptionModule.getSubscription(MOCK_SUBSCRIPTION_ID).cyclesCharged, 0);
    }
}
