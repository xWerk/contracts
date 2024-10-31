// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { MockBadReceiver } from "../../../../mocks/MockBadReceiver.sol";
import { Container_Unit_Concrete_Test } from "../Container.t.sol";
import { Container } from "./../../../../../src/Container.sol";
import { Errors } from "../../../../utils/Errors.sol";
import { Events } from "../../../../utils/Events.sol";

contract WithdrawNative_Unit_Concrete_Test is Container_Unit_Concrete_Test {
    address badReceiver;
    Container badContainer;

    function setUp() public virtual override {
        Container_Unit_Concrete_Test.setUp();

        // Create a bad receiver contract as the owner of the `badContainer` to test for the `NativeWithdrawFailed` error
        badReceiver = address(new MockBadReceiver());
        vm.deal({ account: badReceiver, newBalance: 100 ether });

        // Deploy the `badContainer` container
        address[] memory modules = new address[](1);
        modules[0] = address(mockModule);
        badContainer = deployContainer({ _owner: address(badReceiver), _dockId: 0, _initialModules: modules });
    }

    function test_RevertWhen_CallerNotOwner() external {
        // Make Bob the caller for this test suite who is not the owner of the container
        vm.startPrank({ msgSender: users.bob });

        // Expect the next call to revert with the "Account: not admin or EntryPoint." error
        vm.expectRevert("Account: not admin or EntryPoint.");

        // Run the test
        container.withdrawNative({ amount: 2 ether });
    }

    modifier whenCallerOwner(address caller) {
        // Make `caller` the caller for the next test suite as she's the owner of the container
        vm.startPrank({ msgSender: caller });
        _;
    }

    function test_RevertWhen_InsufficientNativeToWithdraw() external whenCallerOwner(users.eve) {
        // Expect the next call to revert with the {InsufficientNativeToWithdraw} error
        vm.expectRevert(Errors.InsufficientNativeToWithdraw.selector);

        // Run the test
        container.withdrawNative({ amount: 2 ether });
    }

    modifier whenSufficientNativeToWithdraw(Container container) {
        // Deposit sufficient native tokens (ETH) into the container to enable the withdrawal
        (bool success,) = payable(container).call{ value: 2 ether }("");
        if (!success) revert();
        _;
    }

    function test_RevertWhen_NativeWithdrawFailed()
        external
        whenCallerOwner(badReceiver)
        whenSufficientNativeToWithdraw(badContainer)
    {
        // Expect the next call to revert with the {NativeWithdrawFailed} error
        vm.expectRevert(Errors.NativeWithdrawFailed.selector);

        // Run the test
        badContainer.withdrawNative({ amount: 1 ether });
    }

    modifier whenNativeWithdrawSucceeds() {
        _;
    }

    function test_WithdrawNative()
        external
        whenCallerOwner(users.eve)
        whenSufficientNativeToWithdraw(container)
        whenNativeWithdrawSucceeds
    {
        // Store the ETH balance of Eve and {Container} contract before withdrawal
        uint256 balanceOfContainerBefore = address(container).balance;
        uint256 balanceOfEveBefore = address(users.eve).balance;
        uint256 ethToWithdraw = 1 ether;

        // Expect the {AssetWithdrawn} event to be emitted
        vm.expectEmit();
        emit Events.AssetWithdrawn({ to: users.eve, asset: address(0x0), amount: ethToWithdraw });

        // Run the test
        container.withdrawNative({ amount: ethToWithdraw });

        // Assert the ETH balance of the {Container} contract
        uint256 actualBalanceOfContainer = address(container).balance;
        assertEq(actualBalanceOfContainer, balanceOfContainerBefore - ethToWithdraw);

        // Assert the ETH balance of Eve
        uint256 actualBalanceOfEve = address(users.eve).balance;
        assertEq(actualBalanceOfEve, balanceOfEveBefore + ethToWithdraw);
    }
}
