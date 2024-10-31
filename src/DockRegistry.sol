// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseAccountFactory } from "@thirdweb/contracts/prebuilts/account/utils/BaseAccountFactory.sol";
import { IEntryPoint } from "@thirdweb/contracts/prebuilts/account/interface/IEntrypoint.sol";
import { PermissionsEnumerable } from "@thirdweb/contracts/extension/PermissionsEnumerable.sol";
import { EnumerableSet } from "@thirdweb/contracts/external-deps/openzeppelin/utils/structs/EnumerableSet.sol";

import { IDockRegistry } from "./interfaces/IDockRegistry.sol";
import { Space } from "./Space.sol";
import { ModuleKeeper } from "./ModuleKeeper.sol";
import { Errors } from "./libraries/Errors.sol";

/// @title DockRegistry
/// @notice See the documentation in {IDockRegistry}
contract DockRegistry is IDockRegistry, BaseAccountFactory, PermissionsEnumerable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////////////////
                                    STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDockRegistry
    ModuleKeeper public override moduleKeeper;

    /// @inheritdoc IDockRegistry
    mapping(uint256 dockId => address owner) public override ownerOfDock;

    /// @inheritdoc IDockRegistry
    mapping(address space => uint256 dockId) public override dockIdOfSpace;

    /// @dev Counter to keep track of the next dock ID
    uint256 private _dockNextId;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Initializes the {Space} implementation, the Entrypoint, registry admin and sets first dock ID to 1
    constructor(
        address _initialAdmin,
        IEntryPoint _entrypoint,
        ModuleKeeper _moduleKeeper
    ) BaseAccountFactory(address(new Space(_entrypoint, address(this))), address(_entrypoint)) {
        _setupRole(DEFAULT_ADMIN_ROLE, _initialAdmin);

        _dockNextId = 1;
        moduleKeeper = _moduleKeeper;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDockRegistry
    function createAccount(
        address _admin,
        bytes calldata _data
    ) public override(BaseAccountFactory, IDockRegistry) returns (address) {
        // Get the dock ID and initial modules array from the calldata
        // Note: calldata contains a salt (usually the number of accounts created by an admin),
        // dock ID and an array with the initial enabled modules on the account
        (, uint256 dockId, address[] memory initialModules) = abi.decode(_data, (uint256, uint256, address[]));

        // Checks: a new dock must be created first
        if (dockId == 0) {
            // Store the ID of the next dock
            dockId = _dockNextId;

            // Effects: set the owner of the freshly created dock
            ownerOfDock[dockId] = msg.sender;

            // Effects: increment the next dock ID
            // Use unchecked because the dock ID cannot realistically overflow
            unchecked {
                _dockNextId++;
            }
        } else {
            // Checks: `msg.sender` is the dock owner
            if (ownerOfDock[dockId] != msg.sender) {
                revert Errors.CallerNotDockOwner();
            }
        }

        // Interactions: deploy a new {Space} smart account
        address space = super.createAccount(_admin, _data);

        // Assign the ID of the dock to which the new space belongs
        dockIdOfSpace[space] = dockId;

        // Log the {Space} creation
        emit SpaceCreated(_admin, dockId, space, initialModules);

        // Return {Space} smart account address
        return space;
    }

    /// @inheritdoc IDockRegistry
    function transferDockOwnership(uint256 dockId, address newOwner) external {
        // Checks: `msg.sender` is the current owner of the dock
        address currentOwner = ownerOfDock[dockId];
        if (msg.sender != currentOwner) {
            revert Errors.CallerNotDockOwner();
        }

        // Effects: update dock's ownership
        ownerOfDock[dockId] = newOwner;

        // Log the ownership transfer
        emit DockOwnershipTransferred({ dockId: dockId, oldOwner: currentOwner, newOwner: newOwner });
    }

    /// @inheritdoc IDockRegistry
    function updateModuleKeeper(ModuleKeeper newModuleKeeper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Effects: update the {ModuleKeeper} address
        moduleKeeper = newModuleKeeper;

        // Log the update
        emit ModuleKeeperUpdated(newModuleKeeper);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IDockRegistry
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
