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

    // Addresses of the ENSv2 contracts deployed on Sepolia
    // See `deployments/sepolia` in https://github.com/ensdomains/contracts-v2 at the commit pinned in `package.json`
    // (62778d80038e50cb23514eab1b7d66ceb8a41e1c, tagged `v2-mainnet-deployment-1`)
    address constant ETH_REGISTRY = 0xD4eBcbBdF463C9c45784603Db0dDD499BC44A8B4;
    address constant VERIFIABLE_FACTORY = 0xDa70306C98E97eCe36F997a21368e53298572991;
    address constant USER_REGISTRY_IMPL = 0x9BD8a88719068D09ecee662f36C0E3856708366a;
    address constant PERMISSIONED_RESOLVER_IMPL = 0x115eb53F0c60696633855F90b138178Fb40b2b2C;
    address constant UNIVERSAL_RESOLVER = 0xeEeEEEeE14D718C2B47D9923Deab1335E144EeEe;

    // Sepolia block the ENSv2 fork tests are pinned to
    // Note: "werk.eth" is registered on ENSv2 to `WERK_ETH_OWNER` at this block, without a subregistry
    uint256 constant SEPOLIA_FORK_BLOCK = 12_003_911;

    // Owner of "werk.eth" on the Sepolia ENSv2 ETH registry (the `werk-deployer` account)
    address constant WERK_ETH_OWNER = 0xcaE83b7162d64022f7Da3D011fc96761cB14116a;

    // ENSIP-19 default coin type and Base-specific coin type for resolution tests
    // Note: only use `BASE_COIN_TYPE` to test that it fallbacks to `COIN_TYPE_DEFAULT`
    uint256 constant COIN_TYPE_DEFAULT = 1 << 31;
    uint256 constant BASE_COIN_TYPE = 2_147_492_101;
}
