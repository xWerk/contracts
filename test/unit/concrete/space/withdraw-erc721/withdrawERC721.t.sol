// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Space_Unit_Concrete_Test } from "../Space.t.sol";
import { Errors } from "src/libraries/Errors.sol";
import { ISpace } from "src/interfaces/ISpace.sol";
import { IERC721 } from "@openzeppelin/contracts/interfaces/IERC721.sol";

contract WithdrawERC721_Unit_Concrete_Test is Space_Unit_Concrete_Test {
    function setUp() public virtual override {
        Space_Unit_Concrete_Test.setUp();
    }

    function test_RevertWhen_CallerNotOwner() external {
        // Make Bob the caller for this test suite who is not the owner of the space
        vm.startPrank({ msgSender: users.bob });

        // Expect the next call to revert with the {CallerNotEntryPointOrAdmin} error
        vm.expectRevert(Errors.CallerNotEntryPointOrAdmin.selector);

        // Run the test
        space.withdrawERC721({ to: users.bob, collection: IERC721(address(0x0)), tokenId: 1 });
    }

    modifier whenCallerOwner() {
        // Make Eve the caller for the next test suite as she's the owner of the space
        vm.startPrank({ msgSender: users.eve });
        _;
    }

    function test_RevertWhen_NonexistentERC721Token() external whenCallerOwner {
        // Expect the next call to revert with the {ERC721NonexistentToken} error
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256(bytes("ERC721NonexistentToken(uint256)"))), 1));

        // Run the test by attempting to withdraw a nonexistent ERC721 token
        space.withdrawERC721({ to: users.eve, collection: mockERC721, tokenId: 1 });
    }

    modifier whenExistingERC721Token() {
        // Mint an ERC721 token to the space contract
        mockERC721.mint({ to: address(space) });
        _;
    }

    function test_WithdrawERC721() external whenCallerOwner whenExistingERC721Token {
        // Expect the {ERC721Withdrawn} event to be emitted
        vm.expectEmit();
        emit ISpace.ERC721Withdrawn({ to: users.eve, collection: address(mockERC721), tokenId: 1 });

        // Run the test
        space.withdrawERC721({ to: users.eve, collection: mockERC721, tokenId: 1 });

        // Assert the actual and expected owner of the ERC721 token
        address actualOwner = mockERC721.ownerOf(1);
        assertEq(actualOwner, users.eve);
    }
}
