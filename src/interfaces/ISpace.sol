// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC1155Receiver } from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

/// @title ISpace
/// @notice Contract that provides functionalities to store native token (ETH) value and any ERC-20 tokens, allowing
/// external modules to be executed by extending its core functionalities
interface ISpace is IERC165, IERC721Receiver, IERC1155Receiver {
    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
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

    /// @notice Emitted when a `value` amount of ERC-1155 `id` tokens are withdrawn from the space
    /// @param to The address to which the tokens were transferred
    /// @param collection The address of the ERC-1155 collection
    /// @param ids The IDs of the tokens
    /// @param values The amounts of the token types withdrawn
    event ERC1155Withdrawn(address indexed to, address indexed collection, uint256[] ids, uint256[] values);

    /// @notice Emitted when a module execution is successful
    /// @param module The address of the module
    /// @param value The value sent to the module required for the call
    /// @param data The ABI-encoded method called on the module
    event ModuleExecutionSucceded(address indexed module, uint256 value, bytes data);

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the hash of message that should be signed for EIP1271 verification
    /// @param _hash The message hash to sign for the EIP-1271 origin verifying contract
    /// @return messageHash The digest to sign for EIP-1271 verification
    function getMessageHash(bytes32 _hash) external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Executes a call on the `module` module, proving the `value` wei amount for the ABI-encoded `data` method
    /// @param module The address of the module to call
    /// @param value The amount of wei to provide
    /// @param data The ABI-encoded definition of the method (+inputs) to call
    function execute(address module, uint256 value, bytes memory data) external returns (bool success);

    /// @notice Executes multiple calls to one or more `modules` modules
    /// @param modules The addesses of the modules to call
    /// @param values THe amout of wei to provide to each call
    /// @param data The ABI-encoded definition of the method and inputs
    function executeBatch(address[] calldata modules, uint256[] calldata values, bytes[] calldata data) external;

    /// @notice Withdraws an `amount` amount of `asset` ERC-20 token
    ///
    /// Requirements:
    /// - `msg.sender` must be the owner of the space
    ///
    /// @param asset The address of the ERC-20 token to withdraw
    /// @param amount The amount of the ERC-20 token to withdraw
    function withdrawERC20(IERC20 asset, uint256 amount) external;

    /// @notice Withdraws the `tokenId` token of the ERC-721 `collection` collection
    ///
    /// Requirements:
    /// - `msg.sender` must be the owner of the space
    ///
    /// @param collection The address of the ERC-721 collection
    /// @param tokenId The ID of the token to withdraw
    function withdrawERC721(IERC721 collection, uint256 tokenId) external;

    /// @notice Withdraws an `amount` amount of the ERC-1155 `id` token
    ///
    /// Requirements:
    /// - `msg.sender` must be the owner of the space
    ///
    /// @param collection The address of the ERC-1155 collection
    /// @param ids The IDs of tokens to withdraw
    /// @param amounts The amounts of tokens to withdraw
    function withdrawERC1155(IERC1155 collection, uint256[] memory ids, uint256[] memory amounts) external;

    /// @notice Withdraws an `amount` amount of native token (ETH)
    ///
    /// Requirements:
    /// - `msg.sender` must be the owner of the space
    ///
    /// @param amount The amount of the native token to withdraw
    function withdrawNative(uint256 amount) external;
}
