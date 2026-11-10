// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IVerifiableFactory
/// @notice Minimal interface of the ENS `VerifiableFactory` used to deploy ENSv2 registry and resolver proxies
/// @dev Copied from https://github.com/ensdomains/verifiable-factory/blob/c1090aec465ab30d494c96bd7d2a147b4f0b0173/src/IVerifiableFactory.sol
/// as the `contracts-v2` package does not ship its git submodules
interface IVerifiableFactory {
    /// @notice Deploys a UUPS proxy pointing to `implementation` and initializes it with `data`
    /// @dev The CREATE2 salt is `keccak256(abi.encode(msg.sender, salt))`
    function deployProxy(address implementation, uint256 salt, bytes memory data) external returns (address);

    /// @notice Predicts the proxy address for a given deployer and salt
    function predictProxyAddress(address deployer, uint256 salt) external view returns (address proxy);
}
