// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { MockBadReceiver } from "../../../../mocks/MockBadReceiver.sol";
import { Space_Unit_Concrete_Test } from "../Space.t.sol";
import { Space } from "./../../../../../src/Space.sol";
import { Errors } from "../../../../utils/Errors.sol";
import { Events } from "../../../../utils/Events.sol";

contract WithdrawNative_Unit_Concrete_Test is Space_Unit_Concrete_Test {
    address badReceiver;
    Space badSpace;

    function setUp() public virtual override {
        Space_Unit_Concrete_Test.setUp();

        // Create a bad receiver contract as the owner of the `badSpace` to test for the `NativeWithdrawFailed` error
        badReceiver = address(new MockBadReceiver());
        vm.deal({ account: badReceiver, newBalance: 100 ether });

        // Deploy the `badSpace` space
        address[] memory modules = new address[](1);
        modules[0] = address(mockModule);
        badSpace = deploySpace({ _owner: address(badReceiver), _stationId: 0, _initialModules: modules });
    }

    function test_RevertWhen_CallerNotOwner() external {
        // Make Bob the caller for this test suite who is not the owner of the space
        vm.startPrank({ msgSender: users.bob });

        // Expect the next call to revert with the "Account: not admin or EntryPoint." error
        vm.expectRevert("Account: not admin or EntryPoint.");

        // Run the test
        space.withdrawNative({ amount: 2 ether });
    }

    modifier whenCallerOwner(address caller) {
        // Make `caller` the caller for the next test suite as she's the owner of the space
        vm.startPrank({ msgSender: caller });
        _;
    }

    function test_RevertWhen_InsufficientNativeToWithdraw() external whenCallerOwner(users.eve) {
        // Expect the next call to revert with the {InsufficientNativeToWithdraw} error
        vm.expectRevert(Errors.InsufficientNativeToWithdraw.selector);

        // Run the test
        space.withdrawNative({ amount: 2 ether });
    }

    modifier whenSufficientNativeToWithdraw(Space space) {
        // Deposit sufficient native tokens (ETH) into the space to enable the withdrawal
        (bool success,) = payable(space).call{ value: 2 ether }("");
        if (!success) revert();
        _;
    }

    function test_RevertWhen_NativeWithdrawFailed()
        external
        whenCallerOwner(badReceiver)
        whenSufficientNativeToWithdraw(badSpace)
    {
        // Expect the next call to revert with the {NativeWithdrawFailed} error
        vm.expectRevert(Errors.NativeWithdrawFailed.selector);

        // Run the test
        badSpace.withdrawNative({ amount: 1 ether });
    }

    modifier whenNativeWithdrawSucceeds() {
        _;
    }

    function test_WithdrawNative()
        external
        whenCallerOwner(users.eve)
        whenSufficientNativeToWithdraw(space)
        whenNativeWithdrawSucceeds
    {
        // Store the ETH balance of Eve and {Space} contract before withdrawal
        uint256 balanceOfSpaceBefore = address(space).balance;
        uint256 balanceOfEveBefore = address(users.eve).balance;
        uint256 ethToWithdraw = 1 ether;

        // Expect the {AssetWithdrawn} event to be emitted
        vm.expectEmit();
        emit Events.AssetWithdrawn({ to: users.eve, asset: address(0x0), amount: ethToWithdraw });

        // Run the test
        space.withdrawNative({ amount: ethToWithdraw });

        // Assert the ETH balance of the {Space} contract
        uint256 actualBalanceOfSpace = address(space).balance;
        assertEq(actualBalanceOfSpace, balanceOfSpaceBefore - ethToWithdraw);

        // Assert the ETH balance of Eve
        uint256 actualBalanceOfEve = address(users.eve).balance;
        assertEq(actualBalanceOfEve, balanceOfEveBefore + ethToWithdraw);
    }
}
