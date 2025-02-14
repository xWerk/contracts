// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IWerkSubdomainRegistry
/// @notice This is a fork implementation of the IL2Registry contract created by NameStone
/// @dev See the initial implementation here: https://github.com/namestonehq/durin/blob/main/src/IL2Registry.sol
interface IWerkSubdomainRegistry {
    // ERC721 methods
    function ownerOf(uint256 tokenId) external view returns (address);
    // Registry specific methods
    function register(string calldata label, address owner) external;
    // Enables setting address by registrar
    function setAddr(bytes32 labelhash, uint256 coinType, bytes memory value) external;
}
