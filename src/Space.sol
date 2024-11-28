// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC1155Receiver } from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import { AccountCore } from "@thirdweb/contracts/prebuilts/account/utils/AccountCore.sol";
import { IEntryPoint } from "@thirdweb/contracts/prebuilts/account/interface/IEntrypoint.sol";
import { ERC1271 } from "@thirdweb/contracts/eip/ERC1271.sol";
import { EnumerableSet } from "@thirdweb/contracts/external-deps/openzeppelin/utils/structs/EnumerableSet.sol";
import { AccountCoreStorage } from "@thirdweb/contracts/prebuilts/account/utils/AccountCoreStorage.sol";

import { ISpace } from "./interfaces/ISpace.sol";
import { ModuleManager } from "./abstracts/ModuleManager.sol";
import { IModuleManager } from "./interfaces/IModuleManager.sol";
import { Errors } from "./libraries/Errors.sol";
import { StationRegistry } from "./StationRegistry.sol";
import { ModuleKeeper } from "./ModuleKeeper.sol";

/// @title Space
/// @notice See the documentation in {ISpace}
contract Space is ISpace, AccountCore, ERC1271, ModuleManager {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 private constant MSG_TYPEHASH = keccak256("AccountMessage(bytes message)");

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTRUCTOR & INITIALIZER
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Initializes the address of the EIP 4337 factory and EntryPoint contract
    constructor(IEntryPoint _entrypoint, address _factory) AccountCore(_entrypoint, _factory) { }

    /// @notice Initializes the {ModuleKeeper}, enables initial modules and configures the {Space} smart account
    function initialize(address _defaultAdmin, bytes calldata _data) public override {
        (,, address[] memory initialModules) = abi.decode(_data, (uint256, uint256, address[]));

        // Enable the initial module(s)
        ModuleKeeper moduleKeeper = StationRegistry(factory).moduleKeeper();
        _initializeModuleManager(moduleKeeper, initialModules);

        // Initialize the {Space} smart contract
        super.initialize(_defaultAdmin, _data);

        _registerOnFactory();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                RECEIVE & FALLBACK
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Allow space to receive native token (ETH)
    receive() external payable {
        // Log the successful native token deposit
        emit NativeReceived({ from: msg.sender, amount: msg.value });
    }

    /// @dev Fallback function to handle incoming calls with data
    fallback() external payable {
        emit NativeReceived({ from: msg.sender, amount: msg.value });
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Checks whether the caller is the EntryPoint contract or the admin.
    modifier onlyAdminOrEntrypoint() virtual {
        require(msg.sender == address(entryPoint()) || isAdmin(msg.sender), "Account: not admin or EntryPoint.");
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISpace
    function execute(
        address module,
        uint256 value,
        bytes calldata data
    )
        public
        onlyAdminOrEntrypoint
        returns (bool success)
    {
        // Checks: the `module` module is enabled on the smart account
        _checkIfModuleIsEnabled(module);

        // Effects, Interactions: execute the call on the `module` contract
        success = _call(module, value, data);
    }

    /// @inheritdoc ISpace
    function executeBatch(
        address[] calldata modules,
        uint256[] calldata values,
        bytes[] calldata data
    )
        external
        onlyAdminOrEntrypoint
    {
        // Cache the length of the modules array
        uint256 modulesLength = modules.length;

        // Checks: all arrays have the same length
        if (!(modulesLength == data.length && modulesLength == values.length)) revert Errors.WrongArrayLengths();

        // Loop through the calls to execute
        for (uint256 i; i < modulesLength; ++i) {
            // Checks: current module is enabled
            _checkIfModuleIsEnabled(modules[i]);

            // Effects, Interactions: execute all calls on the provided `modules` contracts
            _call(modules[i], values[i], data[i]);
        }
    }

    /// @inheritdoc ISpace
    function withdrawERC20(address to, IERC20 asset, uint256 amount) public onlyAdminOrEntrypoint {
        // Checks: the available ERC20 balance of the space is greater enough to support the withdrawal
        if (amount > asset.balanceOf(address(this))) revert Errors.InsufficientERC20ToWithdraw();

        // Interactions: withdraw by transferring the `amount` to the `to` address
        asset.safeTransfer({ to: to, value: amount });

        // Log the successful ERC-20 token withdrawal
        emit AssetWithdrawn({ to: to, asset: address(asset), amount: amount });
    }

    /// @inheritdoc ISpace
    function withdrawERC721(address to, IERC721 collection, uint256 tokenId) public onlyAdminOrEntrypoint {
        // Checks, Effects, Interactions: withdraw by transferring the `tokenId` token to the `to` address
        // Notes:
        // - we're using `safeTransferFrom` as the owner can be a smart contract
        // therefore the `onERC721Received` hook must be implemented
        collection.safeTransferFrom({ from: address(this), to: to, tokenId: tokenId });

        // Log the successful ERC-721 token withdrawal
        emit ERC721Withdrawn({ to: to, collection: address(collection), tokenId: tokenId });
    }

    /// @inheritdoc ISpace
    function withdrawERC1155(
        address to,
        IERC1155 collection,
        uint256[] memory ids,
        uint256[] memory amounts
    )
        public
        onlyAdminOrEntrypoint
    {
        // Checks, Effects, Interactions: withdraw by transferring the tokens to the `to` address
        // Notes:
        // - we're using `safeTransferFrom` as the owner can be a smart contract
        // therefore the `onERC1155Received` hook must be implemented
        // - depending on the length of the `ids` array, we're using `safeBatchTransferFrom` or `safeTransferFrom`
        if (ids.length > 1) {
            collection.safeBatchTransferFrom({ from: address(this), to: msg.sender, ids: ids, values: amounts, data: "" });
        } else {
            collection.safeTransferFrom({ from: address(this), to: msg.sender, id: ids[0], value: amounts[0], data: "" });
        }

        // Log the successful ERC-1155 token withdrawal
        emit ERC1155Withdrawn({ to: to, collection: address(collection), ids: ids, values: amounts });
    }

    /// @inheritdoc ISpace
    function withdrawNative(address to, uint256 amount) public onlyAdminOrEntrypoint {
        // Checks: the native balance of the space is greater enough to support the withdrawal
        if (amount > address(this).balance) revert Errors.InsufficientNativeToWithdraw();

        // Interactions: withdraw by transferring the `amount` to the `to` address
        (bool success,) = to.call{ value: amount }("");
        // Revert if the call failed
        if (!success) revert Errors.NativeWithdrawFailed();

        // Log the successful native token withdrawal
        emit AssetWithdrawn({ to: to, asset: address(0), amount: amount });
    }

    /// @inheritdoc IModuleManager
    function enableModule(address module) public override onlyAdminOrEntrypoint {
        // Retrieve the address of the {ModuleKeeper}
        ModuleKeeper moduleKeeper = StationRegistry(factory).moduleKeeper();

        // Checks, Effects: enable the module
        _enableModule(moduleKeeper, module);
    }

    /// @inheritdoc IModuleManager
    function disableModule(address module) public override onlyAdminOrEntrypoint {
        // Effects: disable the module
        _disableModule(module);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc ERC1271
    function isValidSignature(
        bytes32 _hash,
        bytes memory _signature
    )
        public
        view
        override
        returns (bytes4 magicValue)
    {
        // Compute the hash of message the should be signed
        bytes32 targetDigest = getMessageHash(_hash);

        // Recover the signer of the hash
        address signer = targetDigest.recover(_signature);

        // Checks: the signer is an admin and return the magic value if so
        if (isAdmin(signer)) {
            return MAGICVALUE;
        }

        // Checks: either `msg.sender` is an approved target or there are no restrictions for approved targets
        EnumerableSet.AddressSet storage targets = _accountPermissionsStorage().approvedTargets[signer];
        if (!(targets.contains(msg.sender) || (targets.length() == 1 && targets.at(0) == address(0)))) {
            revert Errors.CallerNotApprovedTarget();
        }

        // Checks: the signer is an active signer and return the magic value if so
        if (isActiveSigner(signer)) {
            magicValue = MAGICVALUE;
        }
    }

    /// @inheritdoc ISpace
    function getMessageHash(bytes32 _hash) public view returns (bytes32) {
        bytes32 messageHash = keccak256(abi.encode(_hash));
        bytes32 typedDataHash = keccak256(abi.encode(MSG_TYPEHASH, messageHash));
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), typedDataHash));
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == type(ISpace).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId
            || interfaceId == type(IERC721Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @inheritdoc IERC721Receiver
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory
    )
        public
        override
        returns (bytes4)
    {
        // Silence unused variable warning
        operator = operator;

        // Log the successful ERC-721 token receipt
        emit ERC721Received(from, tokenId);

        return this.onERC721Received.selector;
    }

    /// @inheritdoc IERC1155Receiver
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes memory
    )
        public
        override
        returns (bytes4)
    {
        // Silence unused variable warning
        operator = operator;

        // Log the successful ERC-1155 token receipt
        emit ERC1155Received(from, id, value);

        return this.onERC1155Received.selector;
    }

    /// @inheritdoc IERC1155Receiver
    function onERC1155BatchReceived(
        address,
        address from,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory
    )
        public
        override
        returns (bytes4)
    {
        for (uint256 i; i < ids.length; ++i) {
            // Log the successful ERC-1155 token receipt
            emit ERC1155Received(from, ids[i], values[i]);
        }

        return this.onERC1155BatchReceived.selector;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Registers the account on the factory if it hasn't been registered yet
    function _registerOnFactory() internal {
        // Get the address of the factory contract
        StationRegistry factoryContract = StationRegistry(factory);

        // Checks: the smart account is registered on the factory contract
        if (!factoryContract.isRegistered(address(this))) {
            // Otherwise register it
            factoryContract.onRegister(AccountCoreStorage.data().creationSalt);
        }
    }

    /// @dev Executes a low-level call on the `module` contract with the `data` data forwarding the `value` value
    function _call(address module, uint256 value, bytes calldata data) internal returns (bool success) {
        // Execute the call via assembly
        bytes memory result;
        (success, result) = module.call{ value: value }(data);

        // Revert with the same error returned by the module contract if the call failed
        if (!success) {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        } else {
            // Otherwise log the execution success
            emit ModuleExecutionSucceded(module, value, data);
        }
    }
}
