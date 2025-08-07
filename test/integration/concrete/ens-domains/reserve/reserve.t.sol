// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { WerkSubdomainRegistrar } from "src/peripherals/ens-domains/WerkSubdomainRegistrar.sol";
import { Integration_Test } from "test/integration/Integration.t.sol";

contract Reserve_Integration_Concret_Test is Integration_Test {
    function setUp() public virtual override {
        Integration_Test.setUp();
    }

    function test_RevertWhen_SubdomainAlreadyReserved() external {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create the calldata for the reserve method execution
        bytes memory data = abi.encodeWithSignature("reserve(string)", "test");

        // Compute the expiration timestamp
        uint40 expiresAt = uint40(block.timestamp + 30 minutes);

        // Reserve the subdomain
        space.execute({ module: address(werkSubdomainRegistrar), value: 0, data: data });

        // Expect the call to revert with the {AlreadyReserved} error
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256(bytes("AlreadyReserved(uint40)"))), expiresAt));

        // Run the test
        space.execute({ module: address(werkSubdomainRegistrar), value: 0, data: data });
    }

    modifier whenSubdomainNotReserved() {
        _;
    }

    function test_Reserve() external whenSubdomainNotReserved {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create the calldata for the reserve method execution
        bytes memory data = abi.encodeWithSignature("reserve(string)", "test");

        // Compute the expiration timestamp
        uint40 expectedExpiresAt = uint40(block.timestamp + 30 minutes);

        // Expect the reservation call to emit a {SubdomainReserved} event
        vm.expectEmit();
        emit WerkSubdomainRegistrar.SubdomainReserved({
            label: "test",
            owner: address(space),
            expiresAt: expectedExpiresAt
        });

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
