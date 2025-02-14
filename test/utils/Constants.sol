// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

library Constants {
    /// @dev Role identifier for addresses with the default admin role
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /// @dev The address of the native token (ETH) this contract is deployed on following the ERC-7528 standard
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
}
