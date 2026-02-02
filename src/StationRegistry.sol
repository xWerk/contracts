// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IEntryPoint } from "@thirdweb/contracts/prebuilts/account/interface/IEntrypoint.sol";
import { PermissionsEnumerable } from "@thirdweb/contracts/extension/PermissionsEnumerable.sol";
import { EnumerableSet } from "@thirdweb/contracts/external-deps/openzeppelin/utils/structs/EnumerableSet.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import { Space } from "./Space.sol";
import { ModuleKeeper } from "./ModuleKeeper.sol";
import { Errors } from "./libraries/Errors.sol";
import { IStationRegistry } from "./interfaces/IStationRegistry.sol";
import { BaseAccountFactory } from "./utils/BaseAccountFactory.sol";

/// @title StationRegistry
/// @notice See the documentation in {IStationRegistry}
contract StationRegistry is IStationRegistry, BaseAccountFactory, PermissionsEnumerable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Current version of the {StationRegistry} implementation
    string public constant VERSION = "1.0.0";

    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:werk.storage.StationRegistry
    struct StationRegistryStorage {
        /// @inheritdoc IStationRegistry
        ModuleKeeper moduleKeeper;
        /// @inheritdoc IStationRegistry
        mapping(uint256 stationId => address owner) ownerOfStation;
        /// @inheritdoc IStationRegistry
        mapping(address space => uint256 stationId) stationIdOfSpace;
        /// @dev Counter to keep track of the next station ID
        uint256 stationNextId;
    }

    // keccak256(abi.encode(uint256(keccak256("werk.storage.StationRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STATION_REGISTRY_STORAGE_LOCATION =
        0xa5ce9524adfc9e06b7aa62522df0691cf979689201e72471cd0b8da72842ab00;

    /// @dev Retrieves the storage of the {StationRegistry} contract
    function _getStationRegistryStorage() internal pure returns (StationRegistryStorage storage $) {
        assembly {
            $.slot := STATION_REGISTRY_STORAGE_LOCATION
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Disables initializers on the implementation contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() BaseAccountFactory() {
        _disableInitializers();
    }

    /// @notice Initializes the StationRegistry proxy
    /// @param _initialAdmin The address of the initial admin
    /// @param _entrypoint The address of the EIP-4337 EntryPoint contract
    /// @param _moduleKeeper The address of the ModuleKeeper contract
    /// @param _spaceImplementation The address of the Space implementation contract
    function initialize(
        address _initialAdmin,
        IEntryPoint _entrypoint,
        ModuleKeeper _moduleKeeper,
        address _spaceImplementation
    )
        external
        initializer
    {
        __BaseAccountFactory_init(_spaceImplementation, address(_entrypoint));
        _setupRole(DEFAULT_ADMIN_ROLE, _initialAdmin);

        // Retrieve the storage of the {StationRegistry} contract
        StationRegistryStorage storage $ = _getStationRegistryStorage();

        $.stationNextId = 1;
        $.moduleKeeper = _moduleKeeper;
    }

    /// @dev Authorizes an upgrade to a new implementation
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

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

        // Retrieve the storage of the {StationRegistry} contract
        StationRegistryStorage storage $ = _getStationRegistryStorage();

        // Checks: a new station must be created first
        if (stationId == 0) {
            // Store the ID of the next station
            stationId = $.stationNextId;

            // Effects: set the owner of the freshly created station
            $.ownerOfStation[stationId] = msg.sender;

            // Effects: increment the next station ID
            // Use unchecked because the station ID cannot realistically overflow
            unchecked {
                $.stationNextId++;
            }
        } else {
            // Checks: `msg.sender` is the station owner
            if ($.ownerOfStation[stationId] != msg.sender) {
                revert Errors.CallerNotStationOwner();
            }
        }

        // Interactions: deploy a new {Space} smart account
        address space = super.createAccount(_admin, _data);

        // Assign the ID of the station to which the new space belongs
        $.stationIdOfSpace[space] = stationId;

        // Log the {Space} creation
        emit SpaceCreated(_admin, stationId, space);

        // Return {Space} smart account address
        return space;
    }

    /// @inheritdoc IStationRegistry
    function transferStationOwnership(uint256 stationId, address newOwner) external {
        // Retrieve the storage of the {StationRegistry} contract
        StationRegistryStorage storage $ = _getStationRegistryStorage();

        // Checks: `msg.sender` is the current owner of the station
        address currentOwner = $.ownerOfStation[stationId];
        if (msg.sender != currentOwner) {
            revert Errors.CallerNotStationOwner();
        }

        // Effects: update station's ownership
        $.ownerOfStation[stationId] = newOwner;

        // Log the ownership transfer
        emit StationOwnershipTransferred({ stationId: stationId, oldOwner: currentOwner, newOwner: newOwner });
    }

    /// @inheritdoc IStationRegistry
    function updateModuleKeeper(ModuleKeeper newModuleKeeper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Retrieve the storage of the {StationRegistry} contract
        StationRegistryStorage storage $ = _getStationRegistryStorage();

        // Effects: update the {ModuleKeeper} address
        $.moduleKeeper = newModuleKeeper;

        // Log the update
        emit ModuleKeeperUpdated(newModuleKeeper);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IStationRegistry
    function moduleKeeper() external view returns (ModuleKeeper) {
        StationRegistryStorage storage $ = _getStationRegistryStorage();
        return $.moduleKeeper;
    }

    /// @inheritdoc IStationRegistry
    function ownerOfStation(uint256 stationId) external view returns (address) {
        StationRegistryStorage storage $ = _getStationRegistryStorage();
        return $.ownerOfStation[stationId];
    }

    /// @inheritdoc IStationRegistry
    function stationIdOfSpace(address space) external view returns (uint256) {
        StationRegistryStorage storage $ = _getStationRegistryStorage();
        return $.stationIdOfSpace[space];
    }
}
