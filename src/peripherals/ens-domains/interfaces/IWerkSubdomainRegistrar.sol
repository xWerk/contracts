//SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { IFixedSubdomainPricer } from "../pricers/IFixedSubdomainPricer.sol";

interface IWerkSubdomainRegistrar {
    function setupDomain(bytes32 node, IFixedSubdomainPricer pricer, address beneficiary, bool active) external;

    function register(
        bytes32 parentNode,
        string calldata label,
        address newOwner,
        address resolver,
        uint32 fuses,
        bytes[] calldata records
    )
        external
        payable;

    function available(bytes32 node) external view returns (bool);
}
