// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IEntryPoint } from "@thirdweb/contracts/prebuilts/account/interface/IEntrypoint.sol";
import { PermissionsEnumerable } from "@thirdweb/contracts/extension/PermissionsEnumerable.sol";
import { EnumerableSet } from "@thirdweb/contracts/external-deps/openzeppelin/utils/structs/EnumerableSet.sol";

import { Space } from "./Space.sol";
import { ModuleKeeper } from "./ModuleKeeper.sol";
import { Errors } from "./libraries/Errors.sol";
import { IStationRegistry } from "./interfaces/IStationRegistry.sol";
import { BaseAccountFactory } from "./utils/BaseAccountFactory.sol";

/// @title StationRegistry
/// @notice See the documentation in {IStationRegistry}
contract StationRegistry is IStationRegistry, BaseAccountFactory, PermissionsEnumerable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStationRegistry
    ModuleKeeper public override moduleKeeper;

    /// @inheritdoc IStationRegistry
    mapping(uint256 stationId => address owner) public override ownerOfStation;

    /// @inheritdoc IStationRegistry
    mapping(address space => uint256 stationId) public override stationIdOfSpace;

    /// @dev Counter to keep track of the next station ID
    uint256 private _stationNextId;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Initializes the {Space} implementation, the Entrypoint, registry admin and sets first station ID to 1
    constructor(
        address _initialAdmin,
        IEntryPoint _entrypoint,
        ModuleKeeper _moduleKeeper
    )
        BaseAccountFactory(address(new Space(_entrypoint, address(this))), address(_entrypoint))
    {
        _setupRole(DEFAULT_ADMIN_ROLE, _initialAdmin);

        _stationNextId = 1;
        moduleKeeper = _moduleKeeper;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStationRegistry
    function createAccount(
        address _admin,
        bytes calldata _data
    )
        public
        override(BaseAccountFactory, IStationRegistry)
        returns (address)
    {
        // Decode the `stationId` station ID from the calldata
        // Note: `_data` calldata is the result of the `abi.encode` operation
        // between the number of Spaces created by an admin on a specific station
        (, uint256 stationId) = abi.decode(_data, (uint256, uint256));

        // Checks: a new station must be created first
        if (stationId == 0) {
            // Store the ID of the next station
            stationId = _stationNextId;

            // Effects: set the owner of the freshly created station
            ownerOfStation[stationId] = msg.sender;

            // Effects: increment the next station ID
            // Use unchecked because the station ID cannot realistically overflow
            unchecked {
                _stationNextId++;
            }
        } else {
            // Checks: `msg.sender` is the station owner
            if (ownerOfStation[stationId] != msg.sender) {
                revert Errors.CallerNotStationOwner();
            }
        }

        // Interactions: deploy a new {Space} smart account
        address space = super.createAccount(_admin, _data);

        // Assign the ID of the station to which the new space belongs
        stationIdOfSpace[space] = stationId;

        // Log the {Space} creation
        emit SpaceCreated(_admin, stationId, space);

        // Return {Space} smart account address
        return space;
    }

    /// @inheritdoc IStationRegistry
    function transferStationOwnership(uint256 stationId, address newOwner) external {
        // Checks: `msg.sender` is the current owner of the station
        address currentOwner = ownerOfStation[stationId];
        if (msg.sender != currentOwner) {
            revert Errors.CallerNotStationOwner();
        }

        // Effects: update station's ownership
        ownerOfStation[stationId] = newOwner;

        // Log the ownership transfer
        emit StationOwnershipTransferred({ stationId: stationId, oldOwner: currentOwner, newOwner: newOwner });
    }

    /// @inheritdoc IStationRegistry
    function updateModuleKeeper(ModuleKeeper newModuleKeeper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Effects: update the {ModuleKeeper} address
        moduleKeeper = newModuleKeeper;

        // Log the update
        emit ModuleKeeperUpdated(newModuleKeeper);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStationRegistry
    function totalAccountsOfSigner(address signer) public view returns (uint256) {
        return accountsOfSigner[signer].length();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Called in `createAccount`. Initializes the account contract created in `createAccount`.
    function _initializeAccount(address _account, address _admin, bytes calldata _data) internal override {
        Space(payable(_account)).initialize(_admin, _data);
    }
}
