// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Integration_Test } from "../../../Integration.t.sol";
import { Errors } from "../../../../utils/Errors.sol";
import { Events } from "../../../../utils/Events.sol";

contract Reserve_Integration_Concret_Test is Integration_Test {
    function setUp() public virtual override {
        Integration_Test.setUp();
    }

    function test_RevertWhen_CallerNotContract() external {
        // Make Bob the caller in this test suite which is an EOA
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to revert with the {SpaceZeroCodeSize} error
        vm.expectRevert(Errors.SpaceZeroCodeSize.selector);

        // Run the test
        werkSubdomainRegistrar.reserve({ label: "name" });
    }

    modifier whenCallerContract() {
        _;
    }

    function test_RevertWhen_NonCompliantSpace() external whenCallerContract {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create the calldata for the reserve method execution
        bytes memory data = abi.encodeWithSignature("reserve(string)", "test");

        // Expect the call to revert with the {SpaceUnsupportedInterface} error
        vm.expectRevert(Errors.SpaceUnsupportedInterface.selector);

        // Run the test
        mockNonCompliantSpace.execute({ module: address(werkSubdomainRegistrar), value: 0, data: data });
    }

    modifier whenCompliantSpace() {
        _;
    }

    function test_RevertWhen_SubdomainAlreadyReserved() external whenCallerContract whenCompliantSpace {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create the calldata for the reserve method execution
        bytes memory data = abi.encodeWithSignature("reserve(string)", "test");

        // Compute the expiration timestamp
        uint40 expiresAt = uint40(block.timestamp + 30 minutes);

        // Reserve the subdomain
        space.execute({ module: address(werkSubdomainRegistrar), value: 0, data: data });

        // Expect the call to revert with the {AlreadyReserved} error
        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadyReserved.selector, expiresAt));

        // Run the test
        space.execute({ module: address(werkSubdomainRegistrar), value: 0, data: data });
    }

    modifier whenSubdomainNotReserved() {
        _;
    }

    function test_Reserve() external whenCallerContract whenCompliantSpace whenSubdomainNotReserved {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create the calldata for the reserve method execution
        bytes memory data = abi.encodeWithSignature("reserve(string)", "test");

        // Compute the expiration timestamp
        uint40 expectedExpiresAt = uint40(block.timestamp + 30 minutes);

        // Expect the reservation call to emit a {SubdomainReserved} event
        vm.expectEmit();
        emit Events.SubdomainReserved({ label: "test", owner: address(space), expiresAt: expectedExpiresAt });

        // Run the test
        space.execute({ module: address(werkSubdomainRegistrar), value: 0, data: data });

        // Get the reservation
        (address owner, uint40 actualExpiresAt) = werkSubdomainRegistrar.reservations(keccak256(bytes("test")));

        // Assert that actual and expected owner are the same
        assertEq(owner, address(space));

        // Assert that actual and expected expiration timestamp are the same
        assertEq(actualExpiresAt, expectedExpiresAt);
    }
}
