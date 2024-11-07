// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Types } from "./../../src/modules/invoice-module/libraries/Types.sol";
import { Space } from "./../../src/Space.sol";
import { ModuleKeeper } from "./../../src/ModuleKeeper.sol";
import { UD60x18 } from "@prb/math/src/UD60x18.sol";

/// @notice Abstract contract to store all the events emitted in the tested contracts
abstract contract Events {
    /*//////////////////////////////////////////////////////////////////////////
                                    STATION-REGISTRY
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new {Space} contract gets deployed
    /// @param owner The address of the owner
    /// @param stationId The ID of the station to which this {Space} belongs
    /// @param space The address of the {Space}
    /// @param initialModules Array of initially enabled modules
    event SpaceCreated(address indexed owner, uint256 indexed stationId, Space space, address[] initialModules);

    /// @notice Emitted when the ownership of a {Station} is transferred to a new owner
    /// @param stationId The address of the {Station}
    /// @param oldOwner The address of the current owner
    /// @param newOwner The address of the new owner
    event StationOwnershipTransferred(uint256 indexed stationId, address oldOwner, address newOwner);

    /// @notice Emitted when the {ModuleKeeper} address is updated
    /// @param newModuleKeeper The new address of the {ModuleKeeper}
    event ModuleKeeperUpdated(ModuleKeeper newModuleKeeper);

    /// @dev Emitted when the contract has been initialized or reinitialized
    event Initialized(uint64 version);

    /// @dev Emitted when the implementation is upgraded
    event Upgraded(address indexed implementation);

    /*//////////////////////////////////////////////////////////////////////////
                                    CONTAINER
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an `amount` amount of `asset` native tokens (ETH) is deposited on the space
    /// @param from The address of the depositor
    /// @param amount The amount of the deposited ERC-20 token
    event NativeReceived(address indexed from, uint256 amount);

    /// @notice Emitted when an ERC-721 token is received by the space
    /// @param from The address of the depositor
    /// @param tokenId The ID of the received token
    event ERC721Received(address indexed from, uint256 indexed tokenId);

    /// @notice Emitted when an ERC-1155 token is received by the space
    /// @param from The address of the depositor
    /// @param id The ID of the received token
    /// @param value The amount of tokens received
    event ERC1155Received(address indexed from, uint256 indexed id, uint256 value);

    /// @notice Emitted when an `amount` amount of `asset` ERC-20 asset or native ETH is withdrawn from the space
    /// @param to The address to which the tokens were transferred
    /// @param asset The address of the ERC-20 token or zero-address for native ETH
    /// @param amount The withdrawn amount
    event AssetWithdrawn(address indexed to, address indexed asset, uint256 amount);

    /// @notice Emitted when an ERC-721 token is withdrawn from the space
    /// @param to The address to which the token was transferred
    /// @param collection The address of the ERC-721 collection
    /// @param tokenId The ID of the token
    event ERC721Withdrawn(address indexed to, address indexed collection, uint256 tokenId);

    /// @notice Emitted when an ERC-1155 token is withdrawn from the space
    /// @param to The address to which the tokens were transferred
    /// @param ids The IDs of the tokens
    /// @param amounts The amounts of the tokens
    event ERC1155Withdrawn(address indexed to, address indexed collection, uint256[] ids, uint256[] amounts);

    /// @notice Emitted when a module execution is successful
    /// @param module The address of the module
    /// @param value The value sent to the module required for the call
    /// @param data The ABI-encoded method called on the module
    event ModuleExecutionSucceded(address indexed module, uint256 value, bytes data);

    /*//////////////////////////////////////////////////////////////////////////
                                MODULE-MANAGER
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a module is enabled on the space
    /// @param module The address of the enabled module
    event ModuleEnabled(address indexed module, address indexed owner);

    /// @notice Emitted when a module is disabled on the space
    /// @param module The address of the disabled module
    event ModuleDisabled(address indexed module, address indexed owner);

    /*//////////////////////////////////////////////////////////////////////////
                                PAYMENT-MODULE
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a payment request is created
    /// @param id The ID of the payment request
    /// @param recipient The address receiving the payment
    /// @param startTime The timestamp when the payment request takes effect
    /// @param endTime The timestamp by which the payment request must be paid
    /// @param config Struct representing the payment details associated with the payment request
    event RequestCreated(uint256 id, address indexed recipient, uint40 startTime, uint40 endTime, Types.Config config);

    /// @notice Emitted when a payment is made for a payment request
    /// @param id The ID of the payment request
    /// @param payer The address of the payer
    /// @param status The status of the payment request
    /// @param config Struct representing the payment details
    event RequestPaid(uint256 indexed id, address indexed payer, Types.Status status, Types.Config config);

    /// @notice Emitted when a payment request is canceled
    /// @param id The ID of the payment request
    event RequestCanceled(uint256 indexed id);

    /// @notice Emitted when the broker fee is updated
    /// @param oldFee The old broker fee
    /// @param newFee The new broker fee
    event BrokerFeeUpdated(UD60x18 oldFee, UD60x18 newFee);

    /*//////////////////////////////////////////////////////////////////////////
                                    OWNABLE
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the address of the owner is updated
    /// @param oldOwner The address of the previous owner
    /// @param newOwner The address of the new owner
    event OwnershipTransferred(address indexed oldOwner, address newOwner);

    /*//////////////////////////////////////////////////////////////////////////
                                  MODULE-KEEPER
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new module is allowlisted
    /// @param owner The address of the {ModuleKeeper} owner
    /// @param module The address of the module to be allowlisted
    event ModuleAllowlisted(address indexed owner, address indexed module);

    /// @notice Emitted when a module is removed from the allowlist
    /// @param owner The address of the {ModuleKeeper} owner
    /// @param module The address of the module to be removed
    event ModuleRemovedFromAllowlist(address indexed owner, address indexed module);
}
