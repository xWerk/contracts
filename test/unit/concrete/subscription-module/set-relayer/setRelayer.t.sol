// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { SubscriptionModule_Unit_Concrete_Test } from "../SubscriptionModule.t.sol";
import { Errors } from "src/modules/subscription-module/libraries/Errors.sol";
import { ISubscriptionModule } from "src/modules/subscription-module/interfaces/ISubscriptionModule.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract setSignerAddress_Unit_Concrete_Test is SubscriptionModule_Unit_Concrete_Test {
    function setUp() public override {
        SubscriptionModule_Unit_Concrete_Test.setUp();
    }

    function test_RevertWhen_CallerNotOwner() external {
        // Make Bob the caller: Bob is not the module owner
        vm.prank({ msgSender: users.bob });

        // Expect the next call to revert with the {OwnableUnauthorizedAccount} error
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, users.bob));

        // Run the test
        subscriptionModule.setSignerAddress(users.bob);
    }

    function test_RevertWhen_NewSignerZeroAddress() external {
        // Make the admin the caller as it is the module owner
        vm.prank({ msgSender: users.admin });

        // Expect the next call to revert with the {InvalidZeroAddressSigner} error
        vm.expectRevert(Errors.InvalidZeroAddressSigner.selector);

        // Run the test
        subscriptionModule.setSignerAddress(address(0));
    }

    function test_SetSignerAddress() external {
        // The new signer to be set
        address newSigner = makeAddr("newSigner");

        // Make the admin the caller as it is the module owner
        vm.prank({ msgSender: users.admin });

        // Expect the {SignerUpdated} event to be emitted with the old and new signer
        vm.expectEmit(address(subscriptionModule));
        emit ISubscriptionModule.SignerUpdated({ oldSigner: subscriptionSigner, newSigner: newSigner });

        // Run the test
        subscriptionModule.setSignerAddress(newSigner);

        // Assert the signer address was updated
        assertEq(subscriptionModule.getSigner(), newSigner);
    }
}
