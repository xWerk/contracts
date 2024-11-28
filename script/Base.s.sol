// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import { Script } from "forge-std/Script.sol";

contract BaseScript is Script {
    modifier broadcast() {
        vm.startBroadcast();
        _;
        vm.stopBroadcast();
    }
}
