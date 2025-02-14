//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title ISubdomainPricer
/// @notice Contract implementing the basic interface for subdomain pricers
interface ISubdomainPricer {
    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the price details for registering a subdomain
    /// @return The asset to pay the registration fee with and the price
    function getPriceDetails() external returns (address, uint256);
}
