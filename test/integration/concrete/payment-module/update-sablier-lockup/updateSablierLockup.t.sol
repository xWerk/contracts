// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Integration_Test } from "test/integration/Integration.t.sol";
import { ISablierLockup } from "@sablier/lockup/src/interfaces/ISablierLockup.sol";
import { IStreamManager } from "src/modules/payment-module/sablier-lockup/interfaces/IStreamManager.sol";

contract UpdateSablierLockup_Integration_Concret_Test is Integration_Test {
    function setUp() public virtual override {
        Integration_Test.setUp();
    }

    function test_RevertWhen_CallerNotOwner() external {
        // Make Bob the caller in this test suite who is not the owner
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to revert with the {OwnableUnauthorizedAccount} error
        vm.expectRevert(
            abi.encodeWithSelector(bytes4(keccak256(bytes("OwnableUnauthorizedAccount(address)"))), users.bob)
        );

        // Run the test
        paymentModule.updateSablierLockup(ISablierLockup(address(0x123)));
    }

    modifier whenCallerOwner() {
        // Make Admin the caller in this test suite
        vm.startPrank({ msgSender: users.admin });

        _;
    }

    function test_UpdateSablierLockup() external whenCallerOwner {
        ISablierLockup newSablierLockup = ISablierLockup(address(0x123));

        // Expect the {SablierLockupAddressUpdated} to be emitted
        vm.expectEmit();
        emit IStreamManager.SablierLockupAddressUpdated({
            oldAddress: ISablierLockup(address(sablierLockup)),
            newAddress: ISablierLockup(address(0x123))
        });

        // Run the test
        paymentModule.updateSablierLockup(newSablierLockup);

        // Assert the actual and expected broker fee
        ISablierLockup actualSablierLockup = paymentModule.SABLIER_LOCKUP();
        assertEq(address(actualSablierLockup), address(newSablierLockup));
    }
}
