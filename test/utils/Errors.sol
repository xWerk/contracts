// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library Errors {
    /*//////////////////////////////////////////////////////////////////////////
                                    CONTAINER
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when `msg.sender` is not the {Container} contract owner
    error Unauthorized();

    /// @notice Thrown when a native token (ETH) withdrawal fails
    error NativeWithdrawFailed();

    /// @notice Thrown when the available native token (ETH) balance is lower than
    /// the amount requested to be withdrawn
    error InsufficientNativeToWithdraw();

    /// @notice Thrown when the available ERC-20 token balance is lower than
    /// the amount requested to be withdrawn
    error InsufficientERC20ToWithdraw();

    /// @notice Thrown when the deposited ERC-20 token address is zero
    error InvalidAssetZeroAddress();

    /// @notice Thrown when the deposited ERC-20 token amount is zero
    error InvalidAssetZeroAmount();

    /*//////////////////////////////////////////////////////////////////////////
                                  MODULE-MANAGER
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when the requested module to be enabled is not a contract
    error InvalidModule();

    /// @notice Thrown when a container tries to execute a method on a non-enabled module
    error ModuleNotEnabled();
}