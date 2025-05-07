// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { IOwnable } from "src/interfaces/IOwnable.sol";
import { Errors } from "src/libraries/Errors.sol";
import { Ownable_Shared_Test } from "test/unit/shared/Ownable.t.sol";

contract TransferOwnership_Unit_Fuzz_Test is Ownable_Shared_Test {
    function setUp() public virtual override {
        Ownable_Shared_Test.setUp();
    }

    function testFuzz_RevertWhen_CallerNotCurrentOwner(address newOwner) external whenNewOwnerNotZeroAddress {
        // Make sure the new owner is not the current one or the zero address
        vm.assume(newOwner != users.admin && newOwner != address(0));

        // Make Bob the caller for this test suite who is not the current owner
        vm.startPrank({ msgSender: newOwner });

        // Expect the next call to revert with the {Unauthorized} error
        vm.expectRevert(Errors.Unauthorized.selector);

        // Run the test
        ownableMock.transferOwnership(newOwner);
    }

    function testFuzz_TransferOwnership(address newOwner) external whenCallerCurrentOwner whenNewOwnerNotZeroAddress {
        // Make sure the new owner is not the zero address
        vm.assume(newOwner != address(0));

        // Expect the {OwnershipTransferred} event to be emitted
        vm.expectEmit();
        emit IOwnable.OwnershipTransferred({ oldOwner: users.admin, newOwner: newOwner });

        // Run the test
        ownableMock.transferOwnership({ newOwner: newOwner });

        // Assert the actual and expected owner
        address actualOwner = ownableMock.owner();
        assertEq(actualOwner, newOwner);
    }
}
