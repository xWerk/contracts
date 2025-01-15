//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IFixedSubdomainPricer } from "../interfaces/IFixedSubdomainPricer.sol";
import { Ownable } from "../../../abstracts/Ownable.sol";

/// @title FixedSubdomainPricer
/// @notice See the documentation in {IFixedSubdomainPricer}
contract FixedSubdomainPricer is IFixedSubdomainPricer, Ownable {
    /// @dev The address of the native token (ETH) following the ERC-7528 standard
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /*//////////////////////////////////////////////////////////////////////////
                                  PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev The cost of registering a subdomain
    uint256 public override price;

    /// @dev The asset to pay the registration fee with
    address public override asset;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Sets the registration fee, the asset to pay with and the admin authorized to update the price details
    constructor(address _admin, uint256 _price, address _asset) Ownable(_admin) {
        price = _price;
        asset = _asset;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the price details for registering a subdomain
    /// @return The asset to pay the registration fee with and the price
    function getPriceDetails() public view returns (address, uint256) {
        return (asset, price);
    }

    /// @notice Updates the price details for registering a subdomain
    /// @param newPrice The new price to set
    /// @param newAsset The new asset to set
    function updatePriceDetails(uint256 newPrice, address newAsset) public onlyOwner {
        price = newPrice;
        asset = newAsset;
    }
}
