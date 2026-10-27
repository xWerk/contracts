// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title ISpaceFactory
/// @notice Minimal interface of the {StationRegistry} used to check that an address is a Space it deployed
interface ISpaceFactory {
    /// @notice Returns whether `account` is a Space deployed and registered by the factory
    function isRegistered(address account) external view returns (bool);
}
