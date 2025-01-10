//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IBaseSubdomainRegistrar {
    function register(
        bytes32 parentNode,
        string calldata label,
        address newOwner,
        address resolver,
        uint32 fuses,
        bytes[] calldata records
    )
        external;
}
