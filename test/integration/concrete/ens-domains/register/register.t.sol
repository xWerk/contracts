// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Integration_Test } from "../../../Integration.t.sol";
import { Errors } from "../../../../utils/Errors.sol";
import { Events } from "../../../../utils/Events.sol";

contract Register_Integration_Concret_Test is Integration_Test {
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

    function test_WhenSubdomainNotReserved() external whenCallerContract whenCompliantSpace {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Create the calldata for the reserve method execution
        bytes memory data = abi.encodeWithSignature("register(string)", "test");

        // Expect the call to revert with the {ReservationNotFound} error
        vm.expectRevert(Errors.ReservationNotFound.selector);

        // Run the test
        space.execute({ module: address(werkSubdomainRegistrar), value: 0, data: data });
    }

    modifier whenSubdomainReserved() {
        _;
    }

    function test_WhenSubdomainHasAnExpiredReservation()
        external
        whenCallerContract
        whenCompliantSpace
        whenSubdomainReserved
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Reserve the "test" subdomain first
        bytes memory data = abi.encodeWithSignature("reserve(string)", "test");
        space.execute({ module: address(werkSubdomainRegistrar), value: 0, data: data });

        // Warp the time forward by 31 minutes so the reservation expires
        vm.warp(block.timestamp + 31 minutes);

        // Create the calldata for the reserve method execution
        data = abi.encodeWithSignature("register(string)", "test");

        // Expect the call to revert with the {ReservationExpired} error
        vm.expectRevert(Errors.ReservationExpired.selector);

        // Run the test
        space.execute({ module: address(werkSubdomainRegistrar), value: 0, data: data });
    }

    modifier whenSubdomainReservationNotExpired() {
        _;
    }

    function test_RevertWhen_CallerNotReservationOwner()
        external
        whenCallerContract
        whenCompliantSpace
        whenSubdomainReserved
        whenSubdomainReservationNotExpired
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // Reserve the "test" subdomain first from the Eve's Space
        bytes memory data = abi.encodeWithSignature("reserve(string)", "test");
        space.execute({ module: address(werkSubdomainRegistrar), value: 0, data: data });

        // Stop the current prank context
        vm.stopPrank();

        // Create a new space with Bob as the owner and enable the {WerkSubdomainRegistrar} module
        space = deploySpace({ _owner: users.bob, _stationId: 0 });

        // Make Bob the caller for the next calls to simulate a different Space trying to
        // register an already reserved subdomain
        vm.startPrank({ msgSender: users.bob });

        // Create the calldata for the register method execution
        data = abi.encodeWithSignature("register(string)", "test");

        // Compute the expiresAt timestamp of the reservation
        uint40 expiresAt = uint40(block.timestamp + 30 minutes);

        // Expect the call to revert with the {NotReservationOwner} error
        vm.expectRevert(abi.encodeWithSelector(Errors.NotReservationOwner.selector, expiresAt));

        // Run the test
        space.execute({ module: address(werkSubdomainRegistrar), value: 0, data: data });
    }

    modifier whenCallerReservationOwner() {
        _;
    }

    function test_Register()
        external
        whenCallerContract
        whenCompliantSpace
        whenSubdomainReserved
        whenSubdomainReservationNotExpired
        whenCallerReservationOwner
    {
        // Make Eve the caller in this test suite as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });

        // The subdomain to register
        string memory label = "test";

        // Reserve the "test" subdomain first from the Eve's Space
        bytes memory data = abi.encodeWithSignature("reserve(string)", label);
        space.execute({ module: address(werkSubdomainRegistrar), value: 0, data: data });

        // Create the calldata for the register method execution
        data = abi.encodeWithSignature("register(string)", label);

        // Expect the register call to emit a {NameRegistered} event
        vm.expectEmit();
        emit Events.NameRegistered({ label: label, owner: address(space) });

        // Run the test
        space.execute({ module: address(werkSubdomainRegistrar), value: 0, data: data });

        // Check if the subdomain was registered
        bytes32 labelhash = keccak256(abi.encodePacked(label));
        uint256 tokenId = uint256(labelhash);
        assertEq(werkSubdomainRegistry.ownerOf(tokenId), address(space));
    }
}
