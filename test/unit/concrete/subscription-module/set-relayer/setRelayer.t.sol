// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SubscriptionModule_Unit_Concrete_Test } from "../SubscriptionModule.t.sol";
import { Errors } from "src/modules/subscription-module/libraries/Errors.sol";
import { ISubscriptionModule } from "src/modules/subscription-module/interfaces/ISubscriptionModule.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract setRelayer_Unit_Concrete_Test is SubscriptionModule_Unit_Concrete_Test {
    function setUp() public override {
        SubscriptionModule_Unit_Concrete_Test.setUp();
    }

    function test_RevertWhen_CallerNotOwner() external {
        // Make Bob the caller: Bob is not the module owner
        vm.prank({ msgSender: users.bob });

        // Expect the next call to revert with the {OwnableUnauthorizedAccount} error
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, users.bob));

        // Run the test
        subscriptionModule.setRelayer(users.bob);
    }

    function test_RevertWhen_NewRelayerZeroAddress() external {
        // Make the admin the caller as it is the module owner
        vm.prank({ msgSender: users.admin });

        // Expect the next call to revert with the {InvalidZeroAddressRelayer} error
        vm.expectRevert(Errors.InvalidZeroAddressRelayer.selector);

        // Run the test
        subscriptionModule.setRelayer(address(0));
    }

    function test_SetRelayer() external {
        // The new relayer to be set
        address newRelayer = makeAddr("newRelayer");

        // Make the admin the caller as it is the module owner
        vm.prank({ msgSender: users.admin });

        // Expect the {RelayerUpdated} event to be emitted with the old and new relayer
        vm.expectEmit(address(subscriptionModule));
        emit ISubscriptionModule.RelayerUpdated({ oldRelayer: subscriptionRelayer, newRelayer: newRelayer });

        // Run the test
        subscriptionModule.setRelayer(newRelayer);

        // Assert the relayer address was updated
        assertEq(subscriptionModule.getRelayer(), newRelayer);
    }
}
