// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Ownable_Shared_Test } from "../../../shared/Ownable.t.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IOwnable } from "src/interfaces/IOwnable.sol";

contract TransferOwnership_Unit_Concrete_Test is Ownable_Shared_Test {
    function setUp() public virtual override {
        Ownable_Shared_Test.setUp();
    }

    function test_RevertWhen_CallerNotCurrentOwner() external {
        // Make Bob the caller for this test suite who is not the current owner
        vm.startPrank({ msgSender: users.bob });

        // Expect the next call to revert with the {Unauthorized} error
        vm.expectRevert(Errors.Unauthorized.selector);

        // Run the test
        ownableMock.transferOwnership({ newOwner: users.eve });
    }

    function test_RevertWhen_NewOwnerZeroAddress() external whenCallerCurrentOwner {
        // Expect the next call to revert with the {InvalidOwnerZeroAddress} error
        vm.expectRevert(Errors.InvalidOwnerZeroAddress.selector);

        // Run the test by trying to transfer the ownership to the `0x0000000000000000000000000000000000000000` address
        ownableMock.transferOwnership({ newOwner: address(0x0) });
    }

    function test_TransferOwnership() external whenCallerCurrentOwner whenNewOwnerNotZeroAddress {
        // Expect the {OwnershipTransferred} event to be emitted
        vm.expectEmit();
        emit IOwnable.OwnershipTransferred({ oldOwner: users.admin, newOwner: users.eve });

        // Run the test
        ownableMock.transferOwnership({ newOwner: users.eve });

        // Assert the actual and expected owner
        address actualOwner = ownableMock.owner();
        assertEq(actualOwner, users.eve);
    }
}
