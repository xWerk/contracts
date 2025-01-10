//SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    INameWrapper,
    IS_DOT_ETH,
    PARENT_CANNOT_CONTROL,
    CAN_EXTEND_EXPIRY
} from "@ensdomains/ens-contracts/contracts/wrapper/INameWrapper.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC1155Holder } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import { BaseSubdomainRegistrar } from "./BaseSubdomainRegistrar.sol";
import { IWerkSubdomainRegistrar } from "./interfaces/IWerkSubdomainRegistrar.sol";
import { IFixedSubdomainPricer } from "./pricers/IFixedSubdomainPricer.sol";

error ParentNameNotSetup(bytes32 parentNode);

contract WerkSubdomainRegistrar is BaseSubdomainRegistrar, ERC1155Holder, IWerkSubdomainRegistrar {
    constructor(address wrapper, address authorisedIssuer) BaseSubdomainRegistrar(wrapper, authorisedIssuer) { }

    bytes32 private constant ETH_NODE = 0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae;

    function register(
        bytes32 parentNode,
        string calldata label,
        address newOwner,
        address resolver,
        uint32 fuses,
        bytes[] calldata records
    )
        public
        payable
    {
        (, uint32 parentFuses, uint64 expiry) = wrapper.getData(uint256(parentNode));
        uint64 duration = expiry - uint64(block.timestamp);
        if (parentFuses & IS_DOT_ETH == IS_DOT_ETH) {
            duration = duration - GRACE_PERIOD;
        }
        super.register(
            parentNode,
            label,
            newOwner,
            resolver,
            CAN_EXTEND_EXPIRY | PARENT_CANNOT_CONTROL | uint32(fuses),
            duration,
            records
        );
    }

    /// @notice Setup a domain for subdomain registration
    /// @param node The parent node to setup
    /// @param pricer The pricer contract to use when registering subdomains
    /// @param beneficiary The beneficiary of the registration fees
    /// @param active Whether the domain is active
    function setupDomain(
        bytes32 node,
        IFixedSubdomainPricer pricer,
        address beneficiary,
        bool active
    )
        public
        override
        authorised(node)
    {
        _setupDomain(node, pricer, beneficiary, active);
    }

    function available(bytes32 node)
        public
        view
        override(BaseSubdomainRegistrar, IWerkSubdomainRegistrar)
        returns (bool)
    {
        return super.available(node);
    }
}
