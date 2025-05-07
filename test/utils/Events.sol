// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { Types } from "./../../src/modules/payment-module/libraries/Types.sol";
import { Space } from "./../../src/Space.sol";
import { ModuleKeeper } from "./../../src/ModuleKeeper.sol";
import { UD60x18 } from "@prb/math/src/UD60x18.sol";
import { UD21x18 } from "@prb/math/src/UD21x18.sol";

/// @notice Abstract contract to store all the events emitted in the tested contracts
abstract contract Events {
    /*//////////////////////////////////////////////////////////////////////////
                                    STATION-REGISTRY
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new {Space} contract gets deployed
    /// @param owner The address of the owner
    /// @param stationId The ID of the station to which this {Space} belongs
    /// @param space The address of the {Space}
    event SpaceCreated(address indexed owner, uint256 indexed stationId, Space space);

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
    /// @param requestId The ID of the payment request
    /// @param recipient The address receiving the payment
    /// @param startTime The timestamp when the payment request takes effect
    /// @param endTime The timestamp by which the payment request must be paid
    /// @param config Struct representing the payment details associated with the payment request
    event RequestCreated(
        uint256 indexed requestId, address indexed recipient, uint40 startTime, uint40 endTime, Types.Config config
    );

    /// @notice Emitted when a payment is made for a payment request
    /// @param requestId The ID of the payment request
    /// @param payer The address of the payer
    /// @param config Struct representing the payment details
    event RequestPaid(uint256 indexed requestId, address indexed payer, Types.Config config);

    /// @notice Emitted when a payment request is canceled
    /// @param requestId The ID of the payment request
    event RequestCanceled(uint256 indexed requestId);

    /// @notice Emitted when the broker fee is updated
    /// @param oldFee The old broker fee
    /// @param newFee The new broker fee
    event BrokerFeeUpdated(UD60x18 oldFee, UD60x18 newFee);

    /*//////////////////////////////////////////////////////////////////////////
                                COMPENSATION-MODULE
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a compensation plan is created
    /// @param compensationPlanId The ID of the compensation plan
    /// @param recipient The address of the recipient of the compensation plan
    event CompensationPlanCreated(uint256 indexed compensationPlanId, address indexed recipient);

    /// @notice Emitted when a compensation plan component rate per second is adjusted
    /// @param compensationPlanId The ID of the compensation plan
    /// @param componentId The ID of the compensation plan component
    /// @param newRatePerSecond The new rate per second of the compensation plan component
    event ComponentRatePerSecondAdjusted(
        uint256 indexed compensationPlanId, uint96 indexed componentId, UD21x18 newRatePerSecond
    );

    /// @notice Emitted when a compensation plan component stream is deposited
    /// @param compensationPlanId The ID of the compensation plan
    /// @param componentId The ID of the compensation plan component
    /// @param amount The amount deposited to the compensation plan component stream
    event CompensationComponentDeposited(
        uint256 indexed compensationPlanId, uint96 indexed componentId, uint128 amount
    );

    /// @notice Emitted when a compensation plan component stream is withdrawn
    /// @param compensationPlanId The ID of the compensation plan
    /// @param componentId The ID of the compensation plan component
    /// @param withdrawnAmount The amount withdrawn from the compensation plan component stream
    event CompensationComponentWithdrawn(
        uint256 indexed compensationPlanId, uint96 indexed componentId, uint128 withdrawnAmount
    );

    /// @notice Emitted when a compensation plan component stream is paused
    /// @param compensationPlanId The ID of the compensation plan
    /// @param componentId The ID of the compensation plan component
    event CompensationComponentPaused(uint256 indexed compensationPlanId, uint96 indexed componentId);

    /// @notice Emitted when a compensation plan component stream is cancelled
    /// @param compensationPlanId The ID of the compensation plan
    /// @param componentId The ID of the compensation plan component
    event CompensationComponentCancelled(uint256 indexed compensationPlanId, uint96 indexed componentId);

    /// @notice Emitted when a compensation plan component stream is refunded
    /// @param compensationPlanId The ID of the compensation plan
    /// @param componentId The ID of the compensation plan component
    event CompensationComponentRefunded(uint256 indexed compensationPlanId, uint96 indexed componentId);

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
    /// @param modules The addresses of the modules to be allowlisted
    event ModulesAllowlisted(address indexed owner, address[] modules);

    /// @notice Emitted when a module is removed from the allowlist
    /// @param owner The address of the {ModuleKeeper} owner
    /// @param modules The addresses of the modules to be removed
    event ModulesRemovedFromAllowlist(address indexed owner, address[] modules);

    /*//////////////////////////////////////////////////////////////////////////
                                INVOICE-COLLECTION
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an invoice is created
    /// @param to The address of the payment recipient of the invoice
    /// @param tokenId The ID of the NFT representing the invoice
    /// @param paymentRequestId The ID of the payment request associated with the invoice
    event InvoiceMinted(address to, uint256 tokenId, string paymentRequestId);

    /*//////////////////////////////////////////////////////////////////////////
                                   ENS-DOMAINS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new name is registered
    /// @param label The registered label (e.g. "name" in "name.werk.eth")
    /// @param owner The owner of the newly registered name
    event NameRegistered(string indexed label, address indexed owner);

    /// @notice Emitted when a subdomain is reserved
    /// @param label The reserved label (e.g. "name" in "name.werk.eth")
    /// @param owner The owner of the reserved subdomain
    /// @param expiresAt The timestamp at which the reservation expires
    event SubdomainReserved(string indexed label, address indexed owner, uint40 expiresAt);
}
