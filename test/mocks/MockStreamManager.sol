// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { StreamManager } from "./../../src/modules/payment-module/sablier-v2/StreamManager.sol";
import { ISablierV2LockupLinear } from "@sablier/v2-core/src/interfaces/ISablierV2LockupLinear.sol";
import { ISablierV2LockupTranched } from "@sablier/v2-core/src/interfaces/ISablierV2LockupTranched.sol";

/// @title MockStreamManager
/// @notice A mock implementation of the `StreamManager` contract
contract MockStreamManager is StreamManager {
    constructor(
        ISablierV2LockupLinear _sablierLockupLinear,
        ISablierV2LockupTranched _sablierLockupTranched
    )
        StreamManager(_sablierLockupLinear, _sablierLockupTranched)
    { }
}
