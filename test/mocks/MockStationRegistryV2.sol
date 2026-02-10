// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IEntryPoint } from "@thirdweb/contracts/prebuilts/account/interface/IEntrypoint.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { EnumerableSet } from "@thirdweb/contracts/external-deps/openzeppelin/utils/structs/EnumerableSet.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import { ContextUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import { Multicall } from "@thirdweb/contracts/extension/Multicall.sol";

import { ModuleKeeper } from "./../../src/ModuleKeeper.sol";
import { IStationRegistry } from "./../../src/interfaces/IStationRegistry.sol";
import { BaseAccountFactory } from "./../../src/utils/BaseAccountFactory.sol";

/// @title Mock StationRegistry v2
/// @notice Implementation of StationRegistry v2 to use in the upgrade-related tests
contract StationRegistryV2 is IStationRegistry, BaseAccountFactory, OwnableUpgradeable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Current version of the StationRegistry implementation
    string public constant VERSION = "2.0.0";

    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @custom:storage-location erc7201:werk.storage.StationRegistry
    struct StationRegistryStorage {
        /// @inheritdoc IStationRegistry
        ModuleKeeper moduleKeeper;
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

    /*//////////////////////////////////////////////////////////////////////////
                                    INITIALIZER
    //////////////////////////////////////////////////////////////////////////*/

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
        __Ownable_init(_initialAdmin);

        // Retrieve the storage of the {StationRegistry} contract
        StationRegistryStorage storage $ = _getStationRegistryStorage();

        $.moduleKeeper = _moduleKeeper;
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
        // Interactions: deploy a new {Space} smart account
        address space = super.createAccount(_admin, _data);

        // Log the {Space} creation
        emit SpaceCreated(_admin, space);

        // Return {Space} smart account address
        return space;
    }

    /// @inheritdoc IStationRegistry
    function updateModuleKeeper(ModuleKeeper newModuleKeeper) external onlyOwner {
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

    /// @notice New feature available only in V2
    function newFeature() external pure returns (string memory) {
        return "V2";
    }

    /*//////////////////////////////////////////////////////////////////////////
                                INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Authorizes an upgrade to a new implementation
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /*//////////////////////////////////////////////////////////////////////////
                                    OVERRIDES
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Override required due to inheritance conflict between ContextUpgradeable and Multicall
    function _msgSender() internal view override(ContextUpgradeable, Multicall) returns (address) {
        return msg.sender;
    }
}
