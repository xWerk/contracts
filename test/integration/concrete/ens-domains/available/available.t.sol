// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Integration_Test } from "../../../Integration.t.sol";

contract Available_Integration_Concret_Test is Integration_Test {
    function setUp() public virtual override {
        Integration_Test.setUp();
    }

    modifier whenSubdomainRegistered() {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create the calldata for the reserve method execution
        bytes memory data = abi.encodeWithSignature("reserve(string)", "test");

        // Reserve the subdomain
        space.execute({ module: address(werkSubdomainRegistrar), value: 0, data: data });

        _;
    }

    function test_When_SubdomainRegistered() external whenSubdomainRegistered {
        // Expect the call to return false
        assertEq(werkSubdomainRegistrar.available("test"), false);
    }

    modifier whenSubdomainNotRegistered() {
        _;
    }

    modifier whenSubdomainReserved() {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create the calldata for the reserve method execution
        bytes memory data = abi.encodeWithSignature("reserve(string)", "test");

        // Reserve the subdomain
        space.execute({ module: address(werkSubdomainRegistrar), value: 0, data: data });
        _;
    }

    function test_When_SubdomainReserved() external whenSubdomainNotRegistered whenSubdomainReserved {
        // Expect the call to return false
        assertEq(werkSubdomainRegistrar.available("test"), false);
    }

    modifier whenSubdomainNotReserved() {
        _;
    }

    function test_Available() external view whenSubdomainNotRegistered whenSubdomainNotReserved {
        // Expect the call to return true
        assertEq(werkSubdomainRegistrar.available("test"), true);
    }
}
