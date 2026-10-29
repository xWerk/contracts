// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Space } from "src/Space.sol";
import { WerkRegistrar } from "src/peripherals/ensv2/WerkRegistrar.sol";
import { IVerifiableFactory } from "src/peripherals/ensv2/interfaces/IVerifiableFactory.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { WerkENSv2Deployer } from "script/ensv2/WerkENSv2Deployer.sol";
import { IPermissionedRegistry } from "@ensv2/registry/interfaces/IPermissionedRegistry.sol";
import { IStandardRegistry } from "@ensv2/registry/interfaces/IStandardRegistry.sol";
import { IRegistry } from "@ensv2/registry/interfaces/IRegistry.sol";
import { IAddressSetter } from "@ensv2/resolver/interfaces/setters/IAddressSetter.sol";
import { IEnhancedAccessControl } from "@ensv2/access-control/interfaces/IEnhancedAccessControl.sol";
import { NameCoder } from "@ens/contracts/utils/NameCoder.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { Constants } from "../../utils/Constants.sol";
import { Fork_Test } from "../../fork/Fork.t.sol";

/// @notice Minimal interface of the ENS Universal Resolver used to resolve names end-to-end
interface IUniversalResolver {
    function resolve(bytes calldata name, bytes calldata data) external view returns (bytes memory, address);
}

/// @notice Minimal ENSIP-10 interface used to read records directly from the Werk resolver
interface IExtendedResolver {
    function resolve(bytes calldata name, bytes calldata data) external view returns (bytes memory);
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
    address werkResolver;

    bytes32 ethNode;
    bytes32 werkNode;

    /// @dev The trusted backend signer and its private key
    address signer;
    uint256 signerKey;

    /// @dev Default lifetime of the signatures produced by the helpers
    uint40 constant SIGNATURE_TTL = 1 hours;

    /// @dev ERC-1967 slot holding the proxy implementation address
    bytes32 constant ERC1967_IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

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

        // Compute ENS nodes
        ethNode = keccak256(abi.encodePacked(bytes32(0), keccak256("eth")));
        werkNode = keccak256(abi.encodePacked(ethNode, keccak256("werk")));

        // Create the trusted backend signer
        (signer, signerKey) = makeAddrAndKey("signer");

        // Step 1: Deploy the Werk resolver as a `PermissionedResolver` proxy
        werkResolver = WerkENSv2Deployer.deployResolver(
            IVerifiableFactory(Constants.VERIFIABLE_FACTORY),
            Constants.PERMISSIONED_RESOLVER_IMPL,
            WerkENSv2Deployer.RESOLVER_SALT,
            users.admin
        );
        vm.label(werkResolver, "WerkResolver");

        // Step 2: Deploy the Werk registry as a `UserRegistry` proxy
        werkRegistry = WerkENSv2Deployer.deployRegistry(
            IVerifiableFactory(Constants.VERIFIABLE_FACTORY),
            Constants.USER_REGISTRY_IMPL,
            WerkENSv2Deployer.REGISTRY_SALT,
            users.admin
        );
        vm.label(address(werkRegistry), "WerkRegistry");

        // Step 3: Point the existing "werk.eth" on the ETH registry to the Werk registry
        linkWerkLabel();

        // Step 4: Deploy WerkRegistrar as an ERC1967 proxy
        werkRegistrar = WerkENSv2Deployer.deployRegistrar(werkRegistry, werkResolver, users.admin, signer);
        vm.label(address(werkRegistrar), "WerkRegistrar");

        // Step 5: Grant the WerkRegistrar its roles and link the Werk registry to its canonical parent
        vm.startPrank(users.admin);
        WerkENSv2Deployer.configure(
            werkRegistry, werkResolver, address(werkRegistrar), IRegistry(Constants.ETH_REGISTRY)
        );
        vm.stopPrank();

        // Step 6: Allowlist WerkRegistrar in ModuleKeeper so Spaces can call it
        address[] memory modules = new address[](1);
        modules[0] = address(werkRegistrar);
        vm.prank(users.admin);
        moduleKeeper.addToAllowlist(modules);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_ClaimSubname_And_Resolve() external {
        string memory label = "alice";

        // Run the test
        _claimSubname(space, users.alice, label);

        // Verify the registrar getters, which read the ownership from the Werk registry
        bytes32 labelHash = keccak256(bytes(label));
        assertEq(werkRegistrar.getSpaceForLabel(label), address(space), "space for label mismatch");
        assertEq(werkRegistrar.getLabelHashForSpace(address(space)), labelHash, "label for space mismatch");

        // Verify the name is registered in the Werk registry for one year plus the grace period
        assertEq(werkRegistry.getResolver(label), werkResolver, "resolver mismatch");
        assertEq(werkRegistry.getExpiry(uint256(labelHash)), block.timestamp + 395 days, "expiry mismatch");

        // Verify ENSIP-19 default record was set
        bytes memory defaultAddrBytes = _resolveAddress(label, Constants.COIN_TYPE_DEFAULT);
        assertEq(defaultAddrBytes, abi.encodePacked(address(space)), "default address mismatch");

        // ETH (coinType 60) resolves via default
        assertEq(_resolveAddr(label), address(space), "ETH fallback mismatch");

        // Base resolves via default (fallback)
        bytes memory baseAddrBytes = _resolveAddress(label, Constants.BASE_COIN_TYPE);
        assertEq(baseAddrBytes, abi.encodePacked(address(space)), "Base fallback mismatch");
    }

    function test_RevertWhen_SpaceAlreadyHasSubname() external {
        // Alice claims a subname
        _claimSubname(space, users.alice, "alice");

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {SpaceAlreadyHasSubname} error even with a valid signature
        vm.expectRevert(
            abi.encodeWithSelector(
                WerkRegistrar.SpaceAlreadyHasSubname.selector, address(space), keccak256(bytes("alice"))
            )
        );

        // Run the test
        space.execute(address(werkRegistrar), 0, _registerCall(space, "bob"));
    }

    function test_RevertWhen_LabelAlreadyTaken() external {
        // Alice claims the "alice" subname
        _claimSubname(space, users.alice, "alice");

        // Make Bob the caller
        vm.prank(users.bob);

        // Expect the next call to revert with the {LabelAlreadyTaken} error
        vm.expectRevert(
            abi.encodeWithSelector(WerkRegistrar.LabelAlreadyTaken.selector, keccak256(bytes("alice")), address(space))
        );

        // Run the test
        space2.execute(address(werkRegistrar), 0, _registerCall(space2, "alice"));
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
        _claimSubname(space, users.alice, label);

        // Assert that it resolves to the space
        assertEq(_resolveAddr(label), address(space), "label with digits and hyphens should resolve to space");
    }

    function test_ClaimSubname_LabelMaxLength() external {
        // 255 bytes, the longest label a single DNS length byte can encode
        string memory label = _repeat("a", 255);

        // Alice claims the longest allowed label
        _claimSubname(space, users.alice, label);

        // Assert that it resolves to the space
        assertEq(_resolveAddr(label), address(space), "max length label should resolve to space");
    }

    function test_RevertWhen_SignatureExpired() external {
        // Sign a claim that expires now and move past it
        uint40 validUntil = uint40(block.timestamp);
        bytes memory signature = _sign(_registerAction(), address(space), "alice", validUntil, signerKey);
        vm.warp(block.timestamp + 1);

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {SignatureExpired} error
        vm.expectRevert(abi.encodeWithSelector(WerkRegistrar.SignatureExpired.selector, validUntil));

        // Run the test
        space.execute(
            address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.register, ("alice", validUntil, signature))
        );
    }

    function test_RevertWhen_SignedByUntrustedSigner() external {
        // Sign the claim with a key that is not the trusted signer
        (, uint256 untrustedKey) = makeAddrAndKey("untrusted-signer");
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory signature = _sign(_registerAction(), address(space), "alice", validUntil, untrustedKey);

        // Expect the claim to revert with the {InvalidSignature} error
        _expectInvalidSignatureOnRegister(space, users.alice, "alice", validUntil, signature);
    }

    function test_RevertWhen_SignatureForAnotherSpace() external {
        // The backend authorized `space` to claim "alice"
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory signature = _sign(_registerAction(), address(space), "alice", validUntil, signerKey);

        // Expect `space2` replaying it to revert with the {InvalidSignature} error
        _expectInvalidSignatureOnRegister(space2, users.bob, "alice", validUntil, signature);
    }

    function test_RevertWhen_SignatureForAnotherLabel() external {
        // The backend authorized `space` to claim "alice"
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory signature = _sign(_registerAction(), address(space), "alice", validUntil, signerKey);

        // Expect claiming "bob" with it to revert with the {InvalidSignature} error
        _expectInvalidSignatureOnRegister(space, users.alice, "bob", validUntil, signature);
    }

    function test_RevertWhen_SignatureValidUntilTampered() external {
        // The backend authorized the claim until `validUntil`
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory signature = _sign(_registerAction(), address(space), "alice", validUntil, signerKey);

        // Expect extending the deadline to revert with the {InvalidSignature} error
        _expectInvalidSignatureOnRegister(space, users.alice, "alice", validUntil + 1 days, signature);
    }

    function test_RevertWhen_SignatureReused() external {
        // Alice claims "alice" and the owner clears it
        bytes memory registerCall = _registerCall(space, "alice");
        vm.prank(users.alice);
        space.execute(address(werkRegistrar), 0, registerCall);

        string[] memory labels = new string[](1);
        labels[0] = "alice";
        vm.prank(users.admin);
        werkRegistrar.clearLabels(labels);

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect replaying the same signature to revert with the {SignatureAlreadyUsed} error
        vm.expectRevert(WerkRegistrar.SignatureAlreadyUsed.selector);

        // Run the test
        space.execute(address(werkRegistrar), 0, registerCall);
    }

    function test_RevertWhen_SignatureMalformed() external {
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);

        // Expect a signature of the wrong length to revert with the {InvalidSignature} error
        _expectInvalidSignatureOnRegister(space, users.alice, "alice", validUntil, hex"1234");
    }

    function test_RevertWhen_RenewSignatureUsedForRegister() external {
        // The backend authorized `space` to renew "alice"
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory signature = _sign(_renewAction(), address(space), "alice", validUntil, signerKey);

        // Expect claiming with it to revert with the {InvalidSignature} error
        _expectInvalidSignatureOnRegister(space, users.alice, "alice", validUntil, signature);
    }

    function test_RevertWhen_RenewWithoutValidSignature() external {
        // Alice claims a subname and enters the grace period
        _claimSubname(space, users.alice, "alice");
        vm.warp(block.timestamp + 365 days + 1);

        // The backend authorized a claim, not a renewal
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory signature = _sign(_registerAction(), address(space), "alice", validUntil, signerKey);

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {InvalidSignature} error
        vm.expectRevert(WerkRegistrar.InvalidSignature.selector);

        // Run the test
        space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.renew, ("alice", validUntil, signature)));
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
        bytes memory oldSignature = _sign(_registerAction(), address(space), "alice", validUntil, signerKey);
        _expectInvalidSignatureOnRegister(space, users.alice, "alice", validUntil, oldSignature);

        // Assert that the new signer is trusted
        bytes memory newSignature = _sign(_registerAction(), address(space), "alice", validUntil, newSignerKey);
        vm.prank(users.alice);
        space.execute(
            address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.register, ("alice", validUntil, newSignature))
        );
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

    function test_RevertWhen_SpaceUnregistersSubname() external {
        // Alice claims a subname
        _claimSubname(space, users.alice, "alice");

        // Allowlist the Werk registry so the space can call it directly
        // Note: this mirrors a space upgraded to an implementation without the allowlist check
        _allowlistWerkRegistry();

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {EACUnauthorizedAccountRoles} error
        vm.expectPartialRevert(IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector);

        // Run the test
        space.execute(
            address(werkRegistry), 0, abi.encodeCall(IStandardRegistry.unregister, (uint256(keccak256("alice"))))
        );
    }

    function test_RevertWhen_SpaceSetsResolver() external {
        // Alice claims a subname
        _claimSubname(space, users.alice, "alice");

        // Allowlist the Werk registry so the space can call it directly
        _allowlistWerkRegistry();

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {EACUnauthorizedAccountRoles} error
        vm.expectPartialRevert(IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector);

        // Run the test
        space.execute(
            address(werkRegistry),
            0,
            abi.encodeCall(IStandardRegistry.setResolver, (uint256(keccak256("alice")), users.eve))
        );
    }

    function test_RevertWhen_AdminRegistersSubname() external {
        // Make the admin the caller
        vm.prank(users.admin);

        // Expect the next call to revert with the {EACUnauthorizedAccountRoles} error
        vm.expectPartialRevert(IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector);

        // Run the test
        werkRegistry.register("alice", users.admin, IRegistry(address(0)), werkResolver, 0, type(uint64).max);
    }

    function test_RevertWhen_AdminSetsAddress() external {
        // Alice claims a subname
        _claimSubname(space, users.alice, "alice");

        // Make the admin the caller
        vm.prank(users.admin);

        // Expect the next call to revert with the {EACUnauthorizedAccountRoles} error
        vm.expectPartialRevert(IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector);

        // Run the test
        IAddressSetter(werkResolver).setAddress(_dnsEncode("alice"), 60, abi.encodePacked(users.eve));
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
        _claimSubname(space, users.alice, "alice");
        _claimSubname(space2, users.bob, "bob");

        // Assert they resolve correctly
        assertEq(_resolveAddr("alice"), address(space), "alice should resolve to space");
        assertEq(_resolveAddr("bob"), address(space2), "bob should resolve to space2");
    }

    function test_Available() external {
        // Assert that unclaimed label is available
        assertTrue(werkRegistrar.available("alice"), "unclaimed label should be available");

        // Assert that claimed label is not available
        _claimSubname(space, users.alice, "alice");
        assertFalse(werkRegistrar.available("alice"), "claimed label should not be available");
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 EXPIRY & RENEWAL
    //////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_RenewBeforeGracePeriod() external {
        // Alice claims a subname
        _claimSubname(space, users.alice, "alice");

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {RenewalNotOpen} error until the end of the first year
        vm.expectRevert(abi.encodeWithSelector(WerkRegistrar.RenewalNotOpen.selector, block.timestamp + 365 days));

        // Run the test
        space.execute(address(werkRegistrar), 0, _renewCall(space, "alice"));
    }

    function test_Renew_DuringGracePeriod() external {
        // Alice claims a subname
        _claimSubname(space, users.alice, "alice");
        uint256 expiry = werkRegistry.getExpiry(uint256(keccak256("alice")));

        // Warp into the grace period
        vm.warp(block.timestamp + 365 days + 1);

        // Run the test
        _renewSubname(space, users.alice, "alice");

        // Assert that the subname is extended by one year and still resolves to the space
        assertEq(werkRegistry.getExpiry(uint256(keccak256("alice"))), expiry + 365 days, "expiry not extended");
        assertEq(_resolveAddr("alice"), address(space), "renewed subname should resolve to space");
    }

    function test_RevertWhen_RenewByNonOwner() external {
        // Alice claims a subname
        _claimSubname(space, users.alice, "alice");

        // Warp into the grace period
        vm.warp(block.timestamp + 365 days + 1);

        // Make Bob the caller
        vm.prank(users.bob);

        // Expect the next call to revert with the {NotSubnameOwner} error
        vm.expectRevert(abi.encodeWithSelector(WerkRegistrar.NotSubnameOwner.selector, address(space2)));

        // Run the test
        space2.execute(address(werkRegistrar), 0, _renewCall(space2, "alice"));
    }

    function test_RevertWhen_RegisterDuringGracePeriod() external {
        // Alice claims a subname
        _claimSubname(space, users.alice, "alice");

        // Warp into the grace period
        vm.warp(block.timestamp + 366 days);

        // Assert that the subname still resolves to the space during the grace period
        assertEq(_resolveAddr("alice"), address(space), "subname should resolve during grace period");

        // Make Bob the caller
        vm.prank(users.bob);

        // Expect the next call to revert with the {LabelAlreadyTaken} error
        vm.expectRevert(
            abi.encodeWithSelector(WerkRegistrar.LabelAlreadyTaken.selector, keccak256(bytes("alice")), address(space))
        );

        // Run the test
        space2.execute(address(werkRegistrar), 0, _registerCall(space2, "alice"));
    }

    function test_RevertWhen_RenewAfterExpiry() external {
        // Alice claims a subname
        _claimSubname(space, users.alice, "alice");

        // Warp past the grace period
        vm.warp(block.timestamp + 395 days);

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {NotSubnameOwner} error as the subname has expired
        vm.expectRevert(abi.encodeWithSelector(WerkRegistrar.NotSubnameOwner.selector, address(space)));

        // Run the test
        space.execute(address(werkRegistrar), 0, _renewCall(space, "alice"));
    }

    function test_ClaimExpiredLabel_ByAnotherSpace() external {
        // Alice claims a subname, then lets it expire
        _claimSubname(space, users.alice, "alice");
        vm.warp(block.timestamp + 395 days);

        // Run the test
        _claimSubname(space2, users.bob, "alice");

        // Assert that the label now resolves to the new space and the previous space has no active subname
        assertEq(_resolveAddr("alice"), address(space2), "expired label should resolve to the new space");
        assertEq(werkRegistrar.getSpaceForLabel("alice"), address(space2), "space for label mismatch");
        assertEq(werkRegistrar.getLabelHashForSpace(address(space)), bytes32(0), "previous space should be freed");
    }

    function test_ClaimNewLabel_AfterOwnSubnameExpired() external {
        // Alice claims a subname, then lets it expire
        _claimSubname(space, users.alice, "alice");
        vm.warp(block.timestamp + 395 days);

        // Run the test
        _claimSubname(space, users.alice, "alice-new");

        // Assert that the space holds its new subname
        assertEq(_resolveAddr("alice-new"), address(space), "new subname should resolve to space");
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
        _claimSubname(space, users.alice, "alice");
        _claimSubname(space2, users.bob, "bob");

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

        // Assert that the default address record was reset on the Werk resolver
        assertEq(_werkResolverDefaultAddress("alice").length, 0, "default address record should be reset");

        // Assert that a cleared space can claim a new subname
        _claimSubname(space, users.alice, "alice-new");
        assertEq(_resolveAddr("alice-new"), address(space), "new subname should resolve to space");
    }

    function test_RevertWhen_ClearLabelsCallerNotOwner() external {
        // Alice claims a subname
        _claimSubname(space, users.alice, "alice");

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
                                    UPGRADEABILITY
    //////////////////////////////////////////////////////////////////////////*/

    function test_Upgrade_KeepsState() external {
        // Alice claims a subname
        _claimSubname(space, users.alice, "alice");

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
        assertEq(werkRegistrar.RESOLVER(), werkResolver, "resolver mismatch");
        assertEq(werkRegistrar.owner(), users.admin, "owner mismatch");
        assertEq(werkRegistrar.signer(), signer, "signer mismatch");
        assertEq(
            werkRegistrar.getLabelHashForSpace(address(space)), keccak256(bytes("alice")), "label for space mismatch"
        );

        // Assert that the space still cannot claim a second subname after the upgrade
        vm.prank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                WerkRegistrar.SpaceAlreadyHasSubname.selector, address(space), keccak256(bytes("alice"))
            )
        );
        space.execute(address(werkRegistrar), 0, _registerCall(space, "bob"));
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
        implementation.initialize(werkRegistry, werkResolver, users.eve, users.eve);
    }

    function test_RevertWhen_ReinitializeProxy() external {
        // Expect the next call to revert with the {InvalidInitialization} error
        vm.expectRevert(Initializable.InvalidInitialization.selector);

        // Run the test
        werkRegistrar.initialize(werkRegistry, werkResolver, users.eve, users.eve);
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

    /// @dev Claims `label` for `_space` with a fresh signature of the trusted signer
    function _claimSubname(Space _space, address caller, string memory label) internal {
        vm.prank(caller);
        _space.execute(address(werkRegistrar), 0, _registerCall(_space, label));
    }

    /// @dev Renews `label` for `_space` with a fresh signature of the trusted signer
    function _renewSubname(Space _space, address caller, string memory label) internal {
        vm.prank(caller);
        _space.execute(address(werkRegistrar), 0, _renewCall(_space, label));
    }

    /// @dev Builds a {WerkRegistrar.register} call for `_space` signed by the trusted signer
    function _registerCall(Space _space, string memory label) internal view returns (bytes memory) {
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory signature = _sign(_registerAction(), address(_space), label, validUntil, signerKey);
        return abi.encodeCall(WerkRegistrar.register, (label, validUntil, signature));
    }

    /// @dev Builds a {WerkRegistrar.renew} call for `_space` signed by the trusted signer
    function _renewCall(Space _space, string memory label) internal view returns (bytes memory) {
        uint40 validUntil = uint40(block.timestamp + SIGNATURE_TTL);
        bytes memory signature = _sign(_renewAction(), address(_space), label, validUntil, signerKey);
        return abi.encodeCall(WerkRegistrar.renew, (label, validUntil, signature));
    }

    /// @dev Signs the payload the {WerkRegistrar} verifies, the way the backend does
    /// Note: rebuilt independently from the {WerkRegistrar} so that the test catches a mismatch in either one
    function _sign(
        bytes32 action,
        address _space,
        string memory label,
        uint40 validUntil,
        uint256 privateKey
    )
        internal
        view
        returns (bytes memory)
    {
        bytes32 rawHash = keccak256(
            abi.encode(action, address(werkRegistrar), _space, keccak256(bytes(label)), validUntil, block.chainid)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, MessageHashUtils.toEthSignedMessageHash(rawHash));
        return abi.encodePacked(r, s, v);
    }

    /// @dev Action tag of a signed {WerkRegistrar.register} payload
    function _registerAction() internal pure returns (bytes32) {
        return keccak256("WerkRegistrar.register");
    }

    /// @dev Action tag of a signed {WerkRegistrar.renew} payload
    function _renewAction() internal pure returns (bytes32) {
        return keccak256("WerkRegistrar.renew");
    }

    /// @dev Expects claiming `label` from `_space` with the given signature to revert with {InvalidSignature}
    function _expectInvalidSignatureOnRegister(
        Space _space,
        address caller,
        string memory label,
        uint40 validUntil,
        bytes memory signature
    )
        internal
    {
        vm.prank(caller);
        vm.expectRevert(WerkRegistrar.InvalidSignature.selector);
        _space.execute(
            address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.register, (label, validUntil, signature))
        );
    }

    /// @dev Reads the ENSIP-19 default address record of `<label>.werk.eth` directly from the Werk resolver
    function _werkResolverDefaultAddress(string memory label) internal view returns (bytes memory) {
        bytes32 node = keccak256(abi.encodePacked(werkNode, keccak256(bytes(label))));
        bytes memory data = abi.encodeWithSignature("addr(bytes32,uint256)", node, Constants.COIN_TYPE_DEFAULT);

        return abi.decode(IExtendedResolver(werkResolver).resolve(_dnsEncode(label), data), (bytes));
    }

    /// @dev Resolves the `coinType` address of `<label>.werk.eth` through the public Universal Resolver
    function _resolveAddress(string memory label, uint256 coinType) internal view returns (bytes memory) {
        bytes32 node = keccak256(abi.encodePacked(werkNode, keccak256(bytes(label))));
        bytes memory data = abi.encodeWithSignature("addr(bytes32,uint256)", node, coinType);

        (bytes memory result, address resolver) =
            IUniversalResolver(Constants.UNIVERSAL_RESOLVER).resolve(_dnsEncode(label), data);
        assertEq(resolver, werkResolver, "universal resolver found a different resolver");

        return abi.decode(result, (bytes));
    }

    /// @dev Resolves the ETH address of `<label>.werk.eth` through the public Universal Resolver
    function _resolveAddr(string memory label) internal view returns (address) {
        bytes32 node = keccak256(abi.encodePacked(werkNode, keccak256(bytes(label))));
        bytes memory data = abi.encodeWithSignature("addr(bytes32)", node);

        (bytes memory result, address resolver) =
            IUniversalResolver(Constants.UNIVERSAL_RESOLVER).resolve(_dnsEncode(label), data);
        assertEq(resolver, werkResolver, "universal resolver found a different resolver");

        return abi.decode(result, (address));
    }

    /// @dev Expects claiming `label` from the space to revert with the registry's `revertData`
    function _expectRegistryLabelRevert(string memory label, bytes memory revertData) internal {
        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the registry error
        vm.expectRevert(revertData);

        // Run the test
        space.execute(address(werkRegistrar), 0, _registerCall(space, label));
    }

    /// @dev Builds a string of `count` copies of `char`
    function _repeat(string memory char, uint256 count) internal pure returns (string memory result) {
        for (uint256 i; i < count; ++i) {
            result = string.concat(result, char);
        }
    }

    /// @dev Allowlists the Werk registry in the {ModuleKeeper} so that spaces can call it directly
    function _allowlistWerkRegistry() internal {
        address[] memory modules = new address[](1);
        modules[0] = address(werkRegistry);
        vm.prank(users.admin);
        moduleKeeper.addToAllowlist(modules);
    }

    /// @dev Builds the DNS-encoded name `<label>.werk.eth` with the ENS `NameCoder`
    /// Note: independent from the {WerkRegistrar} encoding so that the test catches a bug in either one
    function _dnsEncode(string memory label) internal pure returns (bytes memory) {
        return NameCoder.encode(string.concat(label, ".werk.eth"));
    }
}
