// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SubscriptionModule_Unit_Concrete_Test } from "../SubscriptionModule.t.sol";
import { Errors } from "src/modules/subscription-module/libraries/Errors.sol";
import { ISubscriptionModule } from "src/modules/subscription-module/interfaces/ISubscriptionModule.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract setTreasury_Unit_Concrete_Test is SubscriptionModule_Unit_Concrete_Test {
    function setUp() public override {
        SubscriptionModule_Unit_Concrete_Test.setUp();
    }

    function test_RevertWhen_CallerNotOwner() external {
        // Make Bob the caller: Bob is not the module owner
        vm.prank({ msgSender: users.bob });

        // Expect the next call to revert with the {OwnableUnauthorizedAccount} error
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, users.bob));

        // Run the test
        subscriptionModule.setTreasury(users.bob);
    }

    function test_RevertWhen_NewTreasuryZeroAddress() external {
        // Make the admin the caller as it is the module owner
        vm.prank({ msgSender: users.admin });

        // Expect the next call to revert with the {InvalidZeroAddressTreasury} error
        vm.expectRevert(Errors.InvalidZeroAddressTreasury.selector);

        // Run the test
        subscriptionModule.setTreasury(address(0));
    }

    function test_SetTreasury() external {
        // The new treasury to be set
        address newTreasury = makeAddr("newTreasury");

        // Make the admin the caller as it is the module owner
        vm.prank({ msgSender: users.admin });

        // Expect the {TreasuryUpdated} event to be emitted with the old and new treasury
        vm.expectEmit(address(subscriptionModule));
        emit ISubscriptionModule.TreasuryUpdated({ oldTreasury: werkTreasury, newTreasury: newTreasury });

        // Run the test
        subscriptionModule.setTreasury(newTreasury);

        // Assert the treasury address was updated
        assertEq(subscriptionModule.getTreasury(), newTreasury);
    }
}
