//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ISubdomainPricer } from "./ISubdomainPricer.sol";

/// @title IFixedSubdomainPricer
/// @notice Contract implementing a constant price for registering a subdomain
interface IFixedSubdomainPricer is ISubdomainPricer {
    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the price for registering a subdomain
    function price() external view returns (uint256);

    /// @notice Returns the asset to pay the registration fee with
    function asset() external view returns (address);

    /*//////////////////////////////////////////////////////////////////////////
                                NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Updates the price details for registering a subdomain
    ///
    /// Notes:
    /// - `msg.sender` must be the admin
    ///
    /// @param newPrice The new price to set
    /// @param newAsset The new asset to set
    function updatePriceDetails(uint256 newPrice, address newAsset) external;
}
