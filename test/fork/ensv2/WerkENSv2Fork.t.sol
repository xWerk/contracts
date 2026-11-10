// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { WerkRegistrar } from "src/peripherals/ensv2/WerkRegistrar.sol";
import { IVerifiableFactory } from "src/peripherals/ensv2/interfaces/IVerifiableFactory.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import { WerkENSv2Deployer } from "script/ensv2/WerkENSv2Deployer.sol";
import { IPermissionedRegistry } from "@ensv2/registry/interfaces/IPermissionedRegistry.sol";
import { IStandardRegistry } from "@ensv2/registry/interfaces/IStandardRegistry.sol";
import { IRegistry } from "@ensv2/registry/interfaces/IRegistry.sol";
import { IAddressSetter } from "@ensv2/resolver/interfaces/setters/IAddressSetter.sol";
import { ITextSetter } from "@ensv2/resolver/interfaces/setters/ITextSetter.sol";
import { IPermissionedResolver } from "@ensv2/resolver/interfaces/IPermissionedResolver.sol";
import { IEnhancedAccessControl } from "@ensv2/access-control/interfaces/IEnhancedAccessControl.sol";
import { NameCoder } from "@ens/contracts/utils/NameCoder.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { Constants } from "../../utils/Constants.sol";
import { Fork_Test } from "../../fork/Fork.t.sol";

/// @notice Minimal interface of the ENS Universal Resolver used to resolve names end-to-end
interface IUniversalResolver {
    function resolve(bytes calldata name, bytes calldata data) external view returns (bytes memory, address);
}

/// @notice Fork test against the live ENSv2 deployment on Sepolia
/// Tests the full subname registration and resolution flow through the public Universal Resolver
/// Skipped when the `SEPOLIA_RPC_URL` environment variable is not set
contract WerkENSv2Fork_Test is Fork_Test {
    /*//////////////////////////////////////////////////////////////////////////
                                     VARIABLES
    //////////////////////////////////////////////////////////////////////////*/

    IPermissionedRegistry werkRegistry;
    WerkRegistrar werkRegistrar;

    bytes32 ethNode;
    bytes32 werkNode;

    /// @dev The trusted backend signer and its private key
    address signer;
    uint256 signerKey;

    /// @dev Default lifetime of the signatures produced by the helpers
    uint40 constant SIGNATURE_TTL = 1 hours;

    /// @dev ERC-1967 slot holding the proxy implementation address
    bytes32 constant ERC1967_IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @dev ETH mainnet coin type, which takes precedence over the default address record
    uint256 constant COIN_TYPE_ETH = 60;

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public override {
        // Skip the whole suite when no Sepolia RPC is configured
        if (bytes(vm.envOr("SEPOLIA_RPC_URL", string(""))).length == 0) {
            vm.skip(true);
            return;
        }

        // Fork Sepolia at a pinned block before deploying the Werk infrastructure
        vm.createSelectFork({ urlOrAlias: "sepolia", blockNumber: Constants.SEPOLIA_FORK_BLOCK });

        Fork_Test.setUp();

        // Clear any code at the test users' addresses, as their private keys are public and they may be
        // EIP-7702 delegated on Sepolia, which would make them reject the subname ERC-1155 mint
        vm.etch(users.alice, "");
        vm.etch(users.bob, "");
        vm.etch(users.eve, "");

        // Compute ENS nodes
        ethNode = keccak256(abi.encodePacked(bytes32(0), keccak256("eth")));
        werkNode = keccak256(abi.encodePacked(ethNode, keccak256("werk")));

        // Create the trusted backend signer
        (signer, signerKey) = makeAddrAndKey("signer");

        // Step 1: Deploy the Werk registry as a `UserRegistry` proxy
        werkRegistry = WerkENSv2Deployer.deployRegistry(
            IVerifiableFactory(Constants.VERIFIABLE_FACTORY),
            Constants.USER_REGISTRY_IMPL,
            WerkENSv2Deployer.REGISTRY_SALT,
            users.admin
        );
        vm.label(address(werkRegistry), "WerkRegistry");

        // Step 2: Point the existing "werk.eth" on the ETH registry to the Werk registry
        linkWerkLabel();

        // Step 3: Deploy WerkRegistrar as an ERC1967 proxy
        werkRegistrar = WerkENSv2Deployer.deployRegistrar(
            werkRegistry,
            IVerifiableFactory(Constants.VERIFIABLE_FACTORY),
            Constants.PERMISSIONED_RESOLVER_IMPL,
            users.admin,
            signer
        );
        vm.label(address(werkRegistrar), "WerkRegistrar");

        // Step 4: Grant the WerkRegistrar its roles and link the Werk registry to its canonical parent
        vm.startPrank(users.admin);
        WerkENSv2Deployer.configure(werkRegistry, address(werkRegistrar), IRegistry(Constants.ETH_REGISTRY));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_ClaimSubname_And_Resolve() external {
        string memory label = "alice";

        // Run the test
        _claimSubname(address(space), users.alice, label);

        // Verify the registrar getters
        bytes32 labelHash = keccak256(bytes(label));
        assertEq(werkRegistrar.getSpaceForLabel(label), address(space), "space for label mismatch");
        assertEq(werkRegistrar.getLabelHashForSpace(address(space)), labelHash, "label for space mismatch");

        // Verify the name is held by the admin EOA in the Werk registry for one year plus the grace period
        assertEq(_ownerOf(label), users.alice, "owner mismatch");
        assertEq(werkRegistry.getExpiry(uint256(labelHash)), block.timestamp + 395 days, "expiry mismatch");

        // Verify the name points to the owner's own resolver, deployed on its first claim
        address resolver = werkRegistrar.resolverOf(users.alice);
        assertEq(werkRegistry.getResolver(label), resolver, "resolver mismatch");
        assertGt(resolver.code.length, 0, "resolver not deployed");

        // Verify ENSIP-19 default record was set
        bytes memory defaultAddrBytes = _resolveAddress(label, Constants.COIN_TYPE_DEFAULT);
        assertEq(defaultAddrBytes, abi.encodePacked(address(space)), "default address mismatch");

        // ETH (coinType 60) resolves via default
        assertEq(_resolveAddr(label), address(space), "ETH fallback mismatch");

        // Base resolves via default (fallback)
        bytes memory baseAddrBytes = _resolveAddress(label, Constants.BASE_COIN_TYPE);
        assertEq(baseAddrBytes, abi.encodePacked(address(space)), "Base fallback mismatch");
    }

    function test_ClaimSubname_SpaceNotDeployed() external {
        // A space that is only deployed on another chain, e.g. Base
        address baseSpace = makeAddr("base-space");

        // Run the test
        _claimSubname(baseSpace, users.alice, "alice");

        // Assert that the subname resolves to the space even though it has no code on this chain
        assertEq(baseSpace.code.length, 0, "space should not be deployed");
        assertEq(_resolveAddr("alice"), baseSpace, "subname should resolve to the space");
        assertEq(werkRegistrar.getSpaceForLabel("alice"), baseSpace, "space for label mismatch");
    }

    function test_RevertWhen_SpaceAlreadyHasSubname() external {
        // Alice claims a subname
        _claimSubname(address(space), users.alice, "alice");

        // Expect the next call to revert with the {SpaceAlreadyHasSubname} error even with a valid signature
        vm.expectRevert(
            abi.encodeWithSelector(
                WerkRegistrar.SpaceAlreadyHasSubname.selector, address(space), keccak256(bytes("alice"))
            )
        );

        // Run the test
        _register(address(space), users.alice, "bob");
    }

    function test_RevertWhen_LabelAlreadyTaken() external {
        // Alice claims the "alice" subname
        _claimSubname(address(space), users.alice, "alice");

        // Expect the next call to revert with the {LabelAlreadyTaken} error
        vm.expectRevert(
            abi.encodeWithSelector(WerkRegistrar.LabelAlreadyTaken.selector, keccak256(bytes("alice")), users.alice)
        );

        // Run the test
        _register(address(space2), users.bob, "alice");
    }

    function test_RevertWhen_LabelEmpty() external {
        // Expect the registry to reject the label with the {LabelIsEmpty} error
        _expectRegistryLabelRevert("", abi.encodeWithSelector(NameCoder.LabelIsEmpty.selector));
    }

    function test_RevertWhen_LabelTooLong() external {
        // 256 bytes, one above what a single DNS length byte can encode
        string memory label = _repeat("a", 256);

        // Expect the registry to reject the label with the {LabelIsTooLong} error
        _expectRegistryLabelRevert(label, abi.encodeWithSelector(NameCoder.LabelIsTooLong.selector, label));
    }

    function test_ClaimSubname_LabelWithDigitsAndHyphens() external {
        string memory label = "acme-co-2026";

        // Alice claims a label with digits and inner hyphens
        _claimSubname(address(space), users.alice, label);

        // Assert that it resolves to the space
        assertEq(_resolveAddr(label), address(space), "label with digits and hyphens should resolve to space");
    }

    function test_ClaimSubname_LabelMaxLength() external {
        // 255 bytes, the longest label a single DNS length byte can encode
        string memory label = _repeat("a", 255);

        // Alice claims the longest allowed label
        _claimSubname(address(space), users.alice, label);

        // Assert that it resolves to the space
        assertEq(_resolveAddr(label), address(space), "max length label should resolve to space");
    }

    function test_RevertWhen_SignatureExpired() external {
        // Sign a claim that expires now and move past it
        uint40 validUntil = uint40(block.timestamp);
        bytes memory signature = _signRegister(users.alice, address(space), "alice", validUntil, signerKey);
        vm.warp(block.timestamp + 1);

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {SignatureExpired} error
        vm.expectRevert(abi.encodeWithSelector(WerkRegistrar.SignatureExpired.selector, validUntil));

        // Run the test
        werkRegistrar.register("alice", address(space), validUntil, signature);
    }

    function test_RevertWhen_SignedByUntrustedSigner() external {
        // Sign the claim with a key that is not the trusted signer
        (, uint256 untrustedKey) = makeAddrAndKey("untrusted-signer");
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory signature = _signRegister(users.alice, address(space), "alice", validUntil, untrustedKey);

        // Expect the claim to revert with the {InvalidSignature} error
        _expectInvalidSignatureOnRegister(users.alice, address(space), "alice", validUntil, signature);
    }

    function test_RevertWhen_SignatureForAnotherSpace() external {
        // The backend authorized Bob to claim "alice" for `space`
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory signature = _signRegister(users.bob, address(space), "alice", validUntil, signerKey);

        // Expect using it for `space2` to revert with the {InvalidSignature} error
        _expectInvalidSignatureOnRegister(users.bob, address(space2), "alice", validUntil, signature);
    }

    function test_RevertWhen_SignatureForAnotherOwner() external {
        // The backend authorized Alice to claim "alice" for `space`
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory signature = _signRegister(users.alice, address(space), "alice", validUntil, signerKey);

        // Expect Eve replaying it to revert with the {InvalidSignature} error
        _expectInvalidSignatureOnRegister(users.eve, address(space), "alice", validUntil, signature);
    }

    function test_RevertWhen_SignatureForAnotherLabel() external {
        // The backend authorized `space` to claim "alice"
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory signature = _signRegister(users.alice, address(space), "alice", validUntil, signerKey);

        // Expect claiming "bob" with it to revert with the {InvalidSignature} error
        _expectInvalidSignatureOnRegister(users.alice, address(space), "bob", validUntil, signature);
    }

    function test_RevertWhen_SignatureValidUntilTampered() external {
        // The backend authorized the claim until `validUntil`
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory signature = _signRegister(users.alice, address(space), "alice", validUntil, signerKey);

        // Expect extending the deadline to revert with the {InvalidSignature} error
        _expectInvalidSignatureOnRegister(users.alice, address(space), "alice", validUntil + 1 days, signature);
    }

    function test_RevertWhen_SignatureReused() external {
        // Alice claims "alice" and the owner clears it
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory signature = _signRegister(users.alice, address(space), "alice", validUntil, signerKey);
        vm.prank(users.alice);
        werkRegistrar.register("alice", address(space), validUntil, signature);

        string[] memory labels = new string[](1);
        labels[0] = "alice";
        vm.prank(users.admin);
        werkRegistrar.clearLabels(labels);

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect replaying the same signature to revert with the {SignatureAlreadyUsed} error
        vm.expectRevert(WerkRegistrar.SignatureAlreadyUsed.selector);

        // Run the test
        werkRegistrar.register("alice", address(space), validUntil, signature);
    }

    function test_RevertWhen_SignatureMalformed() external {
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);

        // Expect a signature of the wrong length to revert with the {InvalidSignature} error
        _expectInvalidSignatureOnRegister(users.alice, address(space), "alice", validUntil, hex"1234");
    }

    function test_RevertWhen_RenewSignatureUsedForRegister() external {
        // The backend authorized Alice to renew "alice"
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory signature = _signRenew(users.alice, "alice", validUntil, signerKey);

        // Expect claiming with it to revert with the {InvalidSignature} error
        _expectInvalidSignatureOnRegister(users.alice, address(space), "alice", validUntil, signature);
    }

    function test_RevertWhen_RenewWithoutValidSignature() external {
        // Alice claims a subname and enters the grace period
        _claimSubname(address(space), users.alice, "alice");
        vm.warp(block.timestamp + 365 days + 1);

        // The backend authorized a claim, not a renewal
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory signature = _signRegister(users.alice, address(space), "alice", validUntil, signerKey);

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {InvalidSignature} error
        vm.expectRevert(WerkRegistrar.InvalidSignature.selector);

        // Run the test
        werkRegistrar.renew("alice", validUntil, signature);
    }

    function test_SetSigner() external {
        (address newSigner, uint256 newSignerKey) = makeAddrAndKey("new-signer");

        // Expect the {SignerUpdated} event to be emitted
        vm.expectEmit(address(werkRegistrar));
        emit WerkRegistrar.SignerUpdated(signer, newSigner);

        // Run the test
        vm.prank(users.admin);
        werkRegistrar.setSigner(newSigner);

        // Assert that the signer was rotated
        assertEq(werkRegistrar.signer(), newSigner, "signer not rotated");

        // Assert that the old signer is no longer trusted
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory oldSignature = _signRegister(users.alice, address(space), "alice", validUntil, signerKey);
        _expectInvalidSignatureOnRegister(users.alice, address(space), "alice", validUntil, oldSignature);

        // Assert that the new signer is trusted
        bytes memory newSignature = _signRegister(users.alice, address(space), "alice", validUntil, newSignerKey);
        vm.prank(users.alice);
        werkRegistrar.register("alice", address(space), validUntil, newSignature);
        assertEq(werkRegistrar.getSpaceForLabel("alice"), address(space), "space for label mismatch");
    }

    function test_RevertWhen_SetSignerCallerNotOwner() external {
        // Make Eve the caller
        vm.prank(users.eve);

        // Expect the next call to revert with the {OwnableUnauthorizedAccount} error
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.eve));

        // Run the test
        werkRegistrar.setSigner(users.eve);
    }

    function test_RevertWhen_SetSignerZeroAddress() external {
        // Make the owner the caller
        vm.prank(users.admin);

        // Expect the next call to revert with the {InvalidZeroAddressSigner} error
        vm.expectRevert(WerkRegistrar.InvalidZeroAddressSigner.selector);

        // Run the test
        werkRegistrar.setSigner(address(0));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   ACCESS CONTROL
    //////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_OwnerUnregistersSubname() external {
        // Alice claims a subname
        _claimSubname(address(space), users.alice, "alice");

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {EACUnauthorizedAccountRoles} error
        vm.expectPartialRevert(IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector);

        // Run the test
        werkRegistry.unregister(uint256(keccak256("alice")));
    }

    function test_RevertWhen_OwnerSetsResolver() external {
        // Alice claims a subname
        _claimSubname(address(space), users.alice, "alice");

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {EACUnauthorizedAccountRoles} error
        vm.expectPartialRevert(IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector);

        // Run the test
        werkRegistry.setResolver(uint256(keccak256("alice")), users.eve);
    }

    function test_RevertWhen_OwnerTransfersSubname() external {
        // Alice claims a subname
        _claimSubname(address(space), users.alice, "alice");
        uint256 tokenId = werkRegistry.getTokenId(uint256(keccak256("alice")));

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {TransferUnsafeUntilRegistryIsEmancipated} error
        // Note: once emancipated, the registry still rejects it with {TransferDisallowed}, as the owner holds no
        // `ROLE_CAN_TRANSFER_ADMIN` on its subname
        vm.expectRevert(IPermissionedRegistry.TransferUnsafeUntilRegistryIsEmancipated.selector);

        // Run the test
        IERC1155(address(werkRegistry)).safeTransferFrom(users.alice, users.eve, tokenId, 1, "");
    }

    function test_RevertWhen_AdminRegistersSubname() external {
        // Make the admin the caller
        vm.prank(users.admin);

        // Expect the next call to revert with the {EACUnauthorizedAccountRoles} error
        vm.expectPartialRevert(IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector);

        // Run the test
        werkRegistry.register("alice", users.admin, IRegistry(address(0)), address(0), 0, type(uint64).max);
    }

    function test_CanonicalParent() external view {
        // Assert that the Werk registry points to "werk" on the ETH registry as its parent
        (IRegistry parent, string memory label) = werkRegistry.getParent();
        assertEq(address(parent), Constants.ETH_REGISTRY, "parent mismatch");
        assertEq(label, "werk", "parent label mismatch");

        // Assert that the ETH registry points back to the Werk registry so the link is canonical
        assertEq(
            address(IRegistry(Constants.ETH_REGISTRY).getSubregistry("werk")),
            address(werkRegistry),
            "subregistry mismatch"
        );
    }

    function test_MultipleSpaces_ClaimDifferentSubnames() external {
        // Alice and Bob each claim a subname
        _claimSubname(address(space), users.alice, "alice");
        _claimSubname(address(space2), users.bob, "bob");

        // Assert they resolve correctly
        assertEq(_resolveAddr("alice"), address(space), "alice should resolve to space");
        assertEq(_resolveAddr("bob"), address(space2), "bob should resolve to space2");

        // Assert that each owner got its own resolver
        assertEq(werkRegistry.getResolver("alice"), werkRegistrar.resolverOf(users.alice), "alice resolver mismatch");
        assertEq(werkRegistry.getResolver("bob"), werkRegistrar.resolverOf(users.bob), "bob resolver mismatch");
    }

    function test_Available() external {
        // Assert that unclaimed label is available
        assertTrue(werkRegistrar.available("alice"), "unclaimed label should be available");

        // Assert that claimed label is not available
        _claimSubname(address(space), users.alice, "alice");
        assertFalse(werkRegistrar.available("alice"), "claimed label should not be available");
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  OWNER RECORDS
    //////////////////////////////////////////////////////////////////////////*/

    function test_OwnerSetsTextRecord() external {
        // Alice claims a subname
        _claimSubname(address(space), users.alice, "alice");
        address resolver = werkRegistrar.resolverOf(users.alice);

        // Make Alice the caller
        vm.prank(users.alice);

        // Run the test
        ITextSetter(resolver).setText(_dnsEncode("alice"), "url", "https://alice.xyz");

        // Assert that the record resolves through the Universal Resolver
        assertEq(_resolveText("alice", "url"), "https://alice.xyz", "text record mismatch");
    }

    function test_RevertWhen_OwnerSetsDefaultAddress() external {
        // Alice claims a subname
        _claimSubname(address(space), users.alice, "alice");
        address resolver = werkRegistrar.resolverOf(users.alice);

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {EACUnauthorizedAccountRoles} error
        vm.expectPartialRevert(IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector);

        // Run the test
        IAddressSetter(resolver)
            .setAddress(_dnsEncode("alice"), Constants.COIN_TYPE_DEFAULT, abi.encodePacked(users.eve));
    }

    function test_RevertWhen_OwnerSetsChainAddress() external {
        // Alice claims a subname
        _claimSubname(address(space), users.alice, "alice");
        address resolver = werkRegistrar.resolverOf(users.alice);

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {EACUnauthorizedAccountRoles} error, as the ETH address record
        // would take precedence over the default one
        vm.expectPartialRevert(IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector);

        // Run the test
        IAddressSetter(resolver).setAddress(_dnsEncode("alice"), COIN_TYPE_ETH, abi.encodePacked(users.eve));
    }

    function test_RevertWhen_OwnerLinksRecord() external {
        // Alice claims a subname
        _claimSubname(address(space), users.alice, "alice");
        address resolver = werkRegistrar.resolverOf(users.alice);

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {EACUnauthorizedAccountRoles} error
        vm.expectPartialRevert(IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector);

        // Run the test
        IPermissionedResolver(resolver).linkToRecord(_dnsEncode("alice"), 0);
    }

    function test_RevertWhen_AdminSetsAddress() external {
        // Alice claims a subname
        _claimSubname(address(space), users.alice, "alice");
        address resolver = werkRegistrar.resolverOf(users.alice);

        // Make the admin the caller
        vm.prank(users.admin);

        // Expect the next call to revert with the {EACUnauthorizedAccountRoles} error
        vm.expectPartialRevert(IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector);

        // Run the test
        IAddressSetter(resolver).setAddress(_dnsEncode("alice"), COIN_TYPE_ETH, abi.encodePacked(users.eve));
    }

    function test_OwnerRecords_DoNotAffectOtherSubnames() external {
        // Alice and Bob each claim a subname
        _claimSubname(address(space), users.alice, "alice");
        _claimSubname(address(space2), users.bob, "bob");
        address bobResolver = werkRegistrar.resolverOf(users.bob);

        // Make Bob the caller
        vm.prank(users.bob);

        // Run the test: Bob writes a record for "alice" on his own resolver
        ITextSetter(bobResolver).setText(_dnsEncode("alice"), "url", "https://phish.xyz");

        // Assert that "alice" does not resolve the record, as the registry points it to Alice's resolver
        assertEq(_resolveText("alice", "url"), "", "record leaked to another subname");
    }

    function test_OneOwner_MultipleSpaces() external {
        // Alice claims a subname for each space she administers
        _claimSubname(address(space), users.alice, "acme");
        _claimSubname(address(space2), users.alice, "studio");

        // Assert that both subnames share Alice's resolver
        address resolver = werkRegistrar.resolverOf(users.alice);
        assertEq(werkRegistry.getResolver("acme"), resolver, "acme resolver mismatch");
        assertEq(werkRegistry.getResolver("studio"), resolver, "studio resolver mismatch");

        // Alice sets a different record on each subname
        vm.startPrank(users.alice);
        ITextSetter(resolver).setText(_dnsEncode("acme"), "description", "Design agency");
        ITextSetter(resolver).setText(_dnsEncode("studio"), "description", "Video production");
        vm.stopPrank();

        // Assert that each subname resolves to its own space and keeps its own records
        assertEq(_resolveAddr("acme"), address(space), "acme should resolve to space");
        assertEq(_resolveAddr("studio"), address(space2), "studio should resolve to space2");
        assertEq(_resolveText("acme", "description"), "Design agency", "acme record mismatch");
        assertEq(_resolveText("studio", "description"), "Video production", "studio record mismatch");
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 EXPIRY & RENEWAL
    //////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_RenewBeforeGracePeriod() external {
        // Alice claims a subname
        _claimSubname(address(space), users.alice, "alice");

        // Expect the next call to revert with the {RenewalNotOpen} error until the end of the first year
        vm.expectRevert(abi.encodeWithSelector(WerkRegistrar.RenewalNotOpen.selector, block.timestamp + 365 days));

        // Run the test
        _renew(users.alice, "alice");
    }

    function test_Renew_DuringGracePeriod() external {
        // Alice claims a subname
        _claimSubname(address(space), users.alice, "alice");
        uint64 expiry = werkRegistry.getExpiry(uint256(keccak256("alice")));

        // Warp into the grace period
        vm.warp(block.timestamp + 365 days + 1);

        // Expect the {SubnameRenewed} event to be emitted for the space
        vm.expectEmit(address(werkRegistrar));
        emit WerkRegistrar.SubnameRenewed(address(space), "alice", expiry + 365 days);

        // Run the test
        _renew(users.alice, "alice");

        // Assert that the subname is extended by one year and still resolves to the space
        assertEq(werkRegistry.getExpiry(uint256(keccak256("alice"))), expiry + 365 days, "expiry not extended");
        assertEq(_resolveAddr("alice"), address(space), "renewed subname should resolve to space");
    }

    function test_RevertWhen_RenewByNonOwner() external {
        // Alice claims a subname
        _claimSubname(address(space), users.alice, "alice");

        // Warp into the grace period
        vm.warp(block.timestamp + 365 days + 1);

        // Expect the next call to revert with the {NotSubnameOwner} error
        vm.expectRevert(abi.encodeWithSelector(WerkRegistrar.NotSubnameOwner.selector, users.bob));

        // Run the test
        _renew(users.bob, "alice");
    }

    function test_RevertWhen_RegisterDuringGracePeriod() external {
        // Alice claims a subname
        _claimSubname(address(space), users.alice, "alice");

        // Warp into the grace period
        vm.warp(block.timestamp + 366 days);

        // Assert that the subname still resolves to the space during the grace period
        assertEq(_resolveAddr("alice"), address(space), "subname should resolve during grace period");

        // Expect the next call to revert with the {LabelAlreadyTaken} error
        vm.expectRevert(
            abi.encodeWithSelector(WerkRegistrar.LabelAlreadyTaken.selector, keccak256(bytes("alice")), users.alice)
        );

        // Run the test
        _register(address(space2), users.bob, "alice");
    }

    function test_RevertWhen_RenewAfterExpiry() external {
        // Alice claims a subname
        _claimSubname(address(space), users.alice, "alice");

        // Warp past the grace period
        vm.warp(block.timestamp + 395 days);

        // Expect the next call to revert with the {NotSubnameOwner} error as the subname has expired
        vm.expectRevert(abi.encodeWithSelector(WerkRegistrar.NotSubnameOwner.selector, users.alice));

        // Run the test
        _renew(users.alice, "alice");
    }

    function test_ClaimExpiredLabel_ByAnotherSpace() external {
        // Alice claims a subname and sets a record, then lets it expire
        _claimSubname(address(space), users.alice, "alice");
        _setText(users.alice, "alice", "url", "https://alice.xyz");
        vm.warp(block.timestamp + 395 days);

        // Run the test
        _claimSubname(address(space2), users.bob, "alice");

        // Assert that the label now resolves to the new space and the previous space has no active subname
        assertEq(_resolveAddr("alice"), address(space2), "expired label should resolve to the new space");
        assertEq(werkRegistrar.getSpaceForLabel("alice"), address(space2), "space for label mismatch");
        assertEq(werkRegistrar.getLabelHashForSpace(address(space)), bytes32(0), "previous space should be freed");

        // Assert that the previous owner's records do not carry over to the new space
        assertEq(_resolveText("alice", "url"), "", "previous owner record should not resolve");
    }

    function test_ClaimNewLabel_AfterOwnSubnameExpired() external {
        // Alice claims a subname, then lets it expire
        _claimSubname(address(space), users.alice, "alice");
        vm.warp(block.timestamp + 395 days);

        // Run the test
        _claimSubname(address(space), users.alice, "alice-new");

        // Assert that the space holds its new subname, on the same resolver as before
        assertEq(_resolveAddr("alice-new"), address(space), "new subname should resolve to space");
        assertEq(werkRegistry.getResolver("alice-new"), werkRegistrar.resolverOf(users.alice), "resolver mismatch");
        assertEq(
            werkRegistrar.getLabelHashForSpace(address(space)),
            keccak256(bytes("alice-new")),
            "label for space mismatch"
        );
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    CLEAR LABELS
    //////////////////////////////////////////////////////////////////////////*/

    function test_ClearLabels() external {
        // Alice and Bob each claim a subname
        _claimSubname(address(space), users.alice, "alice");
        _claimSubname(address(space2), users.bob, "bob");

        // Make the owner the caller
        vm.prank(users.admin);

        // Run the test, including an unclaimed and an invalid label that are skipped
        string[] memory labels = new string[](4);
        labels[0] = "alice";
        labels[1] = "bob";
        labels[2] = "unclaimed";
        labels[3] = "Invalid!";
        werkRegistrar.clearLabels(labels);

        // Assert that both labels are free again and the spaces hold no subname
        assertTrue(werkRegistrar.available("alice"), "alice should be available");
        assertTrue(werkRegistrar.available("bob"), "bob should be available");
        assertEq(werkRegistrar.getSpaceForLabel("alice"), address(0), "alice should have no space");
        assertEq(werkRegistrar.getLabelHashForSpace(address(space)), bytes32(0), "space should be freed");
        assertEq(werkRegistrar.getLabelHashForSpace(address(space2)), bytes32(0), "space2 should be freed");

        // Assert that the registry no longer points the label to a resolver
        assertEq(werkRegistry.getResolver("alice"), address(0), "resolver should be cleared");

        // Assert that a cleared space can claim a new subname
        _claimSubname(address(space), users.alice, "alice-new");
        assertEq(_resolveAddr("alice-new"), address(space), "new subname should resolve to space");
    }

    function test_RevertWhen_ClearLabelsCallerNotOwner() external {
        // Alice claims a subname
        _claimSubname(address(space), users.alice, "alice");

        // Make Eve the caller
        vm.prank(users.eve);

        // Expect the next call to revert with the {OwnableUnauthorizedAccount} error
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.eve));

        // Run the test
        string[] memory labels = new string[](1);
        labels[0] = "alice";
        werkRegistrar.clearLabels(labels);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 RESOLVER UPGRADES
    //////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_OwnerUpgradesOwnResolver() external {
        // Alice claims a subname
        _claimSubname(address(space), users.alice, "alice");
        address resolver = werkRegistrar.resolverOf(users.alice);

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {EACUnauthorizedAccountRoles} error
        vm.expectPartialRevert(IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector);

        // Run the test
        UUPSUpgradeable(resolver).upgradeToAndCall(Constants.PERMISSIONED_RESOLVER_IMPL, "");
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    UPGRADEABILITY
    //////////////////////////////////////////////////////////////////////////*/

    function test_Upgrade_KeepsState() external {
        // Alice claims a subname
        _claimSubname(address(space), users.alice, "alice");

        // Deploy a new implementation
        address newImplementation = address(new WerkRegistrar());

        // Make the owner the caller
        vm.prank(users.admin);

        // Run the test
        werkRegistrar.upgradeToAndCall(newImplementation, "");

        // Assert that the proxy points to the new implementation
        bytes32 implementation = vm.load(address(werkRegistrar), ERC1967_IMPLEMENTATION_SLOT);
        assertEq(address(uint160(uint256(implementation))), newImplementation, "implementation not upgraded");

        // Assert that the configuration and the claims survived the upgrade
        assertEq(address(werkRegistrar.WERK_REGISTRY()), address(werkRegistry), "registry mismatch");
        assertEq(address(werkRegistrar.VERIFIABLE_FACTORY()), Constants.VERIFIABLE_FACTORY, "factory mismatch");
        assertEq(
            werkRegistrar.RESOLVER_IMPLEMENTATION(), Constants.PERMISSIONED_RESOLVER_IMPL, "resolver impl mismatch"
        );
        assertEq(werkRegistrar.owner(), users.admin, "owner mismatch");
        assertEq(werkRegistrar.signer(), signer, "signer mismatch");
        assertEq(
            werkRegistrar.getLabelHashForSpace(address(space)), keccak256(bytes("alice")), "label for space mismatch"
        );

        // Assert that the space still cannot claim a second subname after the upgrade
        vm.expectRevert(
            abi.encodeWithSelector(
                WerkRegistrar.SpaceAlreadyHasSubname.selector, address(space), keccak256(bytes("alice"))
            )
        );
        _register(address(space), users.alice, "bob");
    }

    function test_RevertWhen_UpgradeCallerNotOwner() external {
        // Deploy a new implementation
        address newImplementation = address(new WerkRegistrar());

        // Make Eve the caller
        vm.prank(users.eve);

        // Expect the next call to revert with the {OwnableUnauthorizedAccount} error
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, users.eve));

        // Run the test
        werkRegistrar.upgradeToAndCall(newImplementation, "");
    }

    function test_RevertWhen_InitializeImplementation() external {
        // Deploy a new implementation
        WerkRegistrar implementation = new WerkRegistrar();

        // Expect the next call to revert with the {InvalidInitialization} error
        vm.expectRevert(Initializable.InvalidInitialization.selector);

        // Run the test
        implementation.initialize(
            werkRegistry,
            IVerifiableFactory(Constants.VERIFIABLE_FACTORY),
            Constants.PERMISSIONED_RESOLVER_IMPL,
            users.eve,
            users.eve
        );
    }

    function test_RevertWhen_ReinitializeProxy() external {
        // Expect the next call to revert with the {InvalidInitialization} error
        vm.expectRevert(Initializable.InvalidInitialization.selector);

        // Run the test
        werkRegistrar.initialize(
            werkRegistry,
            IVerifiableFactory(Constants.VERIFIABLE_FACTORY),
            Constants.PERMISSIONED_RESOLVER_IMPL,
            users.eve,
            users.eve
        );
    }

    /*//////////////////////////////////////////////////////////////////////////
                            DEPLOYMENT-RELATED FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Points the existing "werk.eth" on the ETH registry to the Werk registry, as its owner does post-deployment
    function linkWerkLabel() internal {
        vm.prank(Constants.WERK_ETH_OWNER);
        IStandardRegistry(Constants.ETH_REGISTRY).setSubregistry(uint256(keccak256("werk")), werkRegistry);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    OTHER HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Claims `label` for `space` from its admin `owner` with a fresh signature of the trusted signer
    function _claimSubname(address space, address owner, string memory label) internal {
        _register(space, owner, label);
    }

    /// @dev Calls {WerkRegistrar.register} from `owner` for `space` with a fresh signature of the trusted signer
    /// Note: the signature is built before the prank so that the prank applies to the registrar call
    function _register(address space, address owner, string memory label) internal {
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory signature = _signRegister(owner, space, label, validUntil, signerKey);
        vm.prank(owner);
        werkRegistrar.register(label, space, validUntil, signature);
    }

    /// @dev Calls {WerkRegistrar.renew} from `owner` with a fresh signature of the trusted signer
    function _renew(address owner, string memory label) internal {
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory signature = _signRenew(owner, label, validUntil, signerKey);
        vm.prank(owner);
        werkRegistrar.renew(label, validUntil, signature);
    }

    /// @dev Signs the {WerkRegistrar.register} payload the way the backend does
    /// Note: rebuilt independently from the {WerkRegistrar} so that the test catches a mismatch in either one
    function _signRegister(
        address owner,
        address space,
        string memory label,
        uint40 validUntil,
        uint256 privateKey
    )
        internal
        view
        returns (bytes memory)
    {
        bytes32 rawHash = keccak256(
            abi.encode(
                keccak256("WerkRegistrar.register"),
                address(werkRegistrar),
                owner,
                space,
                keccak256(bytes(label)),
                validUntil,
                block.chainid
            )
        );
        return _signRaw(rawHash, privateKey);
    }

    /// @dev Signs the {WerkRegistrar.renew} payload the way the backend does
    function _signRenew(
        address owner,
        string memory label,
        uint40 validUntil,
        uint256 privateKey
    )
        internal
        view
        returns (bytes memory)
    {
        bytes32 rawHash = keccak256(
            abi.encode(
                keccak256("WerkRegistrar.renew"),
                address(werkRegistrar),
                owner,
                keccak256(bytes(label)),
                validUntil,
                block.chainid
            )
        );
        return _signRaw(rawHash, privateKey);
    }

    /// @dev Produces the EIP-191 signature of `rawHash`
    function _signRaw(bytes32 rawHash, uint256 privateKey) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, MessageHashUtils.toEthSignedMessageHash(rawHash));
        return abi.encodePacked(r, s, v);
    }

    /// @dev Expects claiming `label` for `space` from `caller` with the given signature to revert with
    /// {InvalidSignature}
    function _expectInvalidSignatureOnRegister(
        address caller,
        address space,
        string memory label,
        uint40 validUntil,
        bytes memory signature
    )
        internal
    {
        vm.prank(caller);
        vm.expectRevert(WerkRegistrar.InvalidSignature.selector);
        werkRegistrar.register(label, space, validUntil, signature);
    }

    /// @dev Sets the `key` text record of `<label>.werk.eth` as `owner` on its resolver
    function _setText(address owner, string memory label, string memory key, string memory value) internal {
        address resolver = werkRegistrar.resolverOf(owner);
        vm.prank(owner);
        ITextSetter(resolver).setText(_dnsEncode(label), key, value);
    }

    /// @dev Returns the holder of `<label>.werk.eth` on the Werk registry
    function _ownerOf(string memory label) internal view returns (address) {
        return werkRegistry.getState(uint256(keccak256(bytes(label)))).latestOwner;
    }

    /// @dev Resolves `data` for `<label>.werk.eth` through the public Universal Resolver
    /// Note: asserts that the Universal Resolver used the resolver the Werk registry points the label to
    function _resolve(string memory label, bytes memory data) internal view returns (bytes memory result) {
        address resolver;
        (result, resolver) = IUniversalResolver(Constants.UNIVERSAL_RESOLVER).resolve(_dnsEncode(label), data);
        assertEq(resolver, werkRegistry.getResolver(label), "universal resolver found a different resolver");
    }

    /// @dev Resolves the `coinType` address of `<label>.werk.eth` through the public Universal Resolver
    function _resolveAddress(string memory label, uint256 coinType) internal view returns (bytes memory) {
        bytes memory data = abi.encodeWithSignature("addr(bytes32,uint256)", _node(label), coinType);
        return abi.decode(_resolve(label, data), (bytes));
    }

    /// @dev Resolves the ETH address of `<label>.werk.eth` through the public Universal Resolver
    function _resolveAddr(string memory label) internal view returns (address) {
        bytes memory data = abi.encodeWithSignature("addr(bytes32)", _node(label));
        return abi.decode(_resolve(label, data), (address));
    }

    /// @dev Resolves the `key` text record of `<label>.werk.eth` through the public Universal Resolver
    function _resolveText(string memory label, string memory key) internal view returns (string memory) {
        bytes memory data = abi.encodeWithSignature("text(bytes32,string)", _node(label), key);
        return abi.decode(_resolve(label, data), (string));
    }

    /// @dev Returns the namehash of `<label>.werk.eth`
    function _node(string memory label) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(werkNode, keccak256(bytes(label))));
    }

    /// @dev Expects claiming `label` from the space to revert with the registry's `revertData`
    function _expectRegistryLabelRevert(string memory label, bytes memory revertData) internal {
        // Build the signature before the prank so that the prank applies to the registrar call
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory signature = _signRegister(users.alice, address(space), label, validUntil, signerKey);

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the registry error
        vm.expectRevert(revertData);

        // Run the test
        werkRegistrar.register(label, address(space), validUntil, signature);
    }

    /// @dev Builds a string of `count` copies of `char`
    function _repeat(string memory char, uint256 count) internal pure returns (string memory result) {
        for (uint256 i; i < count; ++i) {
            result = string.concat(result, char);
        }
    }

    /// @dev Builds the DNS-encoded name `<label>.werk.eth` with the ENS `NameCoder`
    /// Note: independent from the {WerkRegistrar} encoding so that the test catches a bug in either one
    function _dnsEncode(string memory label) internal pure returns (bytes memory) {
        return NameCoder.encode(string.concat(label, ".werk.eth"));
    }
}
