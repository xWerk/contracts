// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Fork_Test } from "./Fork.t.sol";
import { WerkSubdomainRegistrar } from "../../src/peripherals/ens-domains/WerkSubdomainRegistrar.sol";
import { FixedSubdomainPricer } from "../../src/peripherals/ens-domains/pricers/FixedSubdomainPricer.sol";
import { INameWrapper } from "@ensdomains/ens-contracts/contracts/wrapper/INameWrapper.sol";
import { ENSRegistry } from "@ensdomains/ens-contracts/contracts/registry/ENSRegistry.sol";
import { Users } from "../utils/Types.sol";

contract WerkSubdomainRegistrar_Fork_Test is Fork_Test {
    /// @dev The address of the `NameWrapper` contract
    address internal constant NAME_WRAPPER = 0x0635513f179D50A207757E05759CbD106d7dFcE8;

    /// @dev The address of the `PublicResolver` contract
    address internal constant PUBLIC_RESOLVER = 0x8FADE66B79cC9f707aB26799354482EB93a5B7dD;

    /// @dev The address of the `ENSRegistry` contract
    address internal constant ENS = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;

    /// @dev The namehash of the `eth` TLD
    /// See https://docs.ens.domains/resolution/names#algorithm
    bytes32 internal constant ETH_NODE = 0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae;

    /// @dev The address of the `werk.eth` domain owner
    address internal constant WERK_ETH_DOMAIN_OWNER = 0x85E094B259718Be1AF0D8CbBD41dd7409c2200aa;

    /// @dev The namehash of the `werk.eth` domain
    bytes32 internal WERK_ETH_NODE;

    /// @dev The subdomain registrar contract
    WerkSubdomainRegistrar public subdomainRegistrar;

    /// @dev The pricer contract
    FixedSubdomainPricer public pricer;

    function setUp() public virtual override {
        // Fork Ethereum Sepolia at the exact block number when the ENS domain was registered & fuses were set
        vm.createSelectFork({ blockNumber: 7_459_644, urlOrAlias: "sepolia" });

        // Run the fork setup
        Fork_Test.setUp();

        // Deploy the subdomain registrar passing the `NameWrapper` contract address and the authorised issuer
        // Note: the authorised issuer is an account that can issue subdomains without paying the registration fee
        subdomainRegistrar =
            new WerkSubdomainRegistrar({ wrapper: NAME_WRAPPER, authorisedIssuer: address(users.admin) });

        // Deploy the pricer contract
        pricer = new FixedSubdomainPricer({ _admin: address(users.admin), _price: 0, _asset: address(0) });

        // Compute the namehash of the `werk.eth` parent node
        WERK_ETH_NODE = keccak256(abi.encodePacked(ETH_NODE, keccak256(bytes("werk"))));

        // Make the `werk.eth` domain owner the caller in the next test suite
        vm.startPrank({ msgSender: WERK_ETH_DOMAIN_OWNER });

        // Setup the domain to allow for subdomain registration
        subdomainRegistrar.setupDomain({
            node: WERK_ETH_NODE,
            pricer: pricer,
            beneficiary: address(users.admin),
            active: true
        });

        // Grant the subdomain registrar approval to manage the `werk.eth` subdomains
        INameWrapper(NAME_WRAPPER).setApprovalForAll({ operator: address(subdomainRegistrar), approved: true });
    }

    function testFork_Register() external {
        // Run the test
        subdomainRegistrar.register({
            parentNode: WERK_ETH_NODE,
            label: "bob",
            newOwner: address(users.bob),
            resolver: PUBLIC_RESOLVER,
            fuses: 327_680,
            records: new bytes[](0)
        });

        // Compute the namehash of the `bob.werk.eth` subdomain
        bytes32 node = keccak256(abi.encodePacked(WERK_ETH_NODE, keccak256(bytes("bob"))));

        // Check that the subdomain was registered
        assertFalse(subdomainRegistrar.available(node));

        // Check that the subdomain owner is Bob
        // Note: we need to check this condition in the `NameWrapper` contract and not in the `ENSRegistry` contract
        // as the owner stored in the `ENSRegistry` contract is the `NameWrapper` contract address
        assertEq(INameWrapper(NAME_WRAPPER).ownerOf(uint256(node)), address(users.bob));
    }
}
