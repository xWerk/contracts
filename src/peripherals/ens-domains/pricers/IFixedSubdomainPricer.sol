//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// @title IFixedSubdomainPricer
/// @notice Contract used to set the price details for registering a subdomain
interface IFixedSubdomainPricer {
    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the price for registering a subdomain
    function price() external view returns (uint256);

    /// @notice Returns the asset to pay the registration fee with
    function asset() external view returns (address);

    /// @notice Returns the price details for registering a subdomain
    /// @return The asset to pay the registration fee with and the price
    function getPriceDetails() external returns (address, uint256);

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
