// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import { UD21x18 } from "@prb/math/src/UD21x18.sol";

library Constants {
    /// @dev Role identifier for addresses with the default admin role
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /// @dev The address of the native token (ETH) this contract is deployed on following the ERC-7528 standard
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev The rate per second of a compensation component
    UD21x18 public constant RATE_PER_SECOND = UD21x18.wrap(0.001e18); // 86.4 daily

    // Addresses of the ENSv2 contracts deployed on anvil
    address constant HCA_FACTORY = 0x0165878A594ca255338adfa4d48449f69242Eb8F;
    address constant SIMPLE_REGISTRY_METADATA = 0xa513E6E4b8f2a923D98304ec87F64353C4D5C853;
    address constant ETH_REGISTRY = 0x9E545E3C0baAB3E08CdfD552C960A1050f373042;
    address constant ETH_REGISTRAR = 0x5f3f1dBD7B74C6B46e8c44f98792A1dAf8d69154;

    // PermissionedResolverImpl deployed on anvil
    address constant PERMISSIONED_RESOLVER_IMPL = 0x1613beB3B2C4f22Ee086B2b38C1476A3cE7f78E8;

    // ENSv2 devnet named accounts
    address constant OWNER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant WERK_OWNER = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;

    // ENSIP-19 default coin type and Base-specific coin type for resolution tests
    // Note: only use `BASE_COIN_TYPE` to test that it fallbacks to `COIN_TYPE_DEFAULT`
    uint256 constant COIN_TYPE_DEFAULT = 1 << 31;
    uint256 constant BASE_COIN_TYPE = 2_147_492_101;
}
