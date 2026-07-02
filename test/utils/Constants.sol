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

    /*//////////////////////////////////////////////////////////////////////////
                                SUBSCRIPTION-MODULE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev The default per-cycle charge of a mock subscription (10 USDT, 6 decimals)
    uint128 public constant SUBSCRIPTION_AMOUNT = 10e6;

    /// @dev The default number of seconds between two consecutive subscription cycles (30 days)
    uint40 public constant SUBSCRIPTION_INTERVAL = 30 days;

    /// @dev The default total number of cycles of a mock subscription
    uint16 public constant SUBSCRIPTION_CYCLES = 12;

    /// @dev The default plan identifier of a mock subscription
    uint8 public constant SUBSCRIPTION_TIER = 1;

    /// @dev The default lifetime of backend-signed subscription terms (quote expiry window)
    uint40 public constant SUBSCRIPTION_QUOTE_TTL = 1 hours;
}
