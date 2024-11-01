// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { ISpace } from "./../../src/interfaces/ISpace.sol";
import { Errors } from "./../../src/modules/invoice-module/libraries/Errors.sol";

/// @notice A mock implementation of a boilerplate module that creates multiple items and
/// associates them with the corresponding {Space} contract
contract MockModule {
    mapping(address space => uint256[]) public itemsOf;

    uint256 private _nextItemIf;

    event ModuleItemCreated(uint256 indexed id);

    /// @dev Allow only calls from contracts implementing the {ISpace} interface
    modifier onlySpace() {
        // Checks: the sender is a valid non-zero code size contract
        if (msg.sender.code.length == 0) {
            revert Errors.SpaceZeroCodeSize();
        }

        // Checks: the sender implements the ERC-165 interface required by {ISpace}
        bytes4 interfaceId = type(ISpace).interfaceId;
        if (!IERC165(msg.sender).supportsInterface(interfaceId)) revert Errors.SpaceUnsupportedInterface();
        _;
    }

    function createModuleItem() external onlySpace returns (uint256 id) {
        // Get the next module item ID
        id = _nextItemIf;

        itemsOf[msg.sender].push(id);

        unchecked {
            _nextItemIf = id + 1;
        }

        emit ModuleItemCreated(id);
    }

    function getItemsOf(address owner) external view returns (uint256[] memory items) {
        uint256 length = itemsOf[owner].length;

        items = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            items[i] = itemsOf[owner][i];
        }
    }
}
