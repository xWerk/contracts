// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import { Script } from "forge-std/Script.sol";

contract BaseScript is Script {
    /// @dev Junk mnemonic seed phrase use as a fallback in case there is no mnemonic set in the `.env` file
    string internal constant TEST_MNEMONIC = "test test test test test test test test test test test junk";

    /// @dev Used to derive the deployer's address
    string internal mnemonic;

    /// @dev Stores the deployer address
    address deployer;

    constructor() {
        address from = vm.envOr({ name: "DEPLOYER", defaultValue: address(0) });
        if (from != address(0)) {
            deployer = from;
        } else {
            mnemonic = vm.envOr({ name: "MNEMONIC", defaultValue: TEST_MNEMONIC });
            (deployer, ) = deriveRememberKey(mnemonic, 0);
        }
    }

    modifier broadcast() {
        vm.startBroadcast(deployer);
        _;
        vm.stopBroadcast();
    }
}
