// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Ownable } from "./../../src/abstracts/Ownable.sol";

/// @title MockOwnable
/// @notice A mock implementation that uses the `onlyOwner` auth mechanism
contract MockOwnable is Ownable {
    constructor(address _owner) Ownable(_owner) { }
}
