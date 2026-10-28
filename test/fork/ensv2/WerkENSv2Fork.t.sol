// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Space } from "src/Space.sol";
import { MockNonCompliantSpace } from "../../mocks/MockNonCompliantSpace.sol";
import { MockUnregisteredSpace } from "../../mocks/MockUnregisteredSpace.sol";
import { WerkRegistrar } from "src/peripherals/ensv2/WerkRegistrar.sol";
import { IVerifiableFactory } from "src/peripherals/ensv2/interfaces/IVerifiableFactory.sol";
import { ISpaceFactory } from "src/peripherals/ensv2/interfaces/ISpaceFactory.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { WerkENSv2Deployer } from "script/ensv2/WerkENSv2Deployer.sol";
import { IPermissionedRegistry } from "@ensv2/registry/interfaces/IPermissionedRegistry.sol";
import { IStandardRegistry } from "@ensv2/registry/interfaces/IStandardRegistry.sol";
import { IRegistry } from "@ensv2/registry/interfaces/IRegistry.sol";
import { IAddressSetter } from "@ensv2/resolver/interfaces/setters/IAddressSetter.sol";
import { IEnhancedAccessControl } from "@ensv2/access-control/interfaces/IEnhancedAccessControl.sol";
import { NameCoder } from "@ens/contracts/utils/NameCoder.sol";
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
        werkRegistrar = WerkENSv2Deployer.deployRegistrar(
            werkRegistry, werkResolver, ISpaceFactory(address(stationRegistry)), users.admin
        );
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

        // Step 1: Space reserves the label
        _reserveSubname(space, users.alice, label);

        // Step 2: Space claims the subname
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
        // Alice reserves and registers a subname
        _reserveAndRegisterSubname(space, users.alice, "alice");

        // Make alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {SpaceAlreadyHasSubname} error as a space with an active
        // subname cannot even reserve a second one
        vm.expectRevert(
            abi.encodeWithSelector(
                WerkRegistrar.SpaceAlreadyHasSubname.selector, address(space), keccak256(bytes("alice"))
            )
        );

        // Run the test
        space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.reserve, ("bob")));
    }

    function test_RevertWhen_LabelAlreadyTaken() external {
        // Alice reserves and claims the "alice" subname
        _reserveAndRegisterSubname(space, users.alice, "alice");

        // Make Bob the caller
        vm.prank(users.bob);

        // Expect the next call to revert with the {LabelAlreadyTaken} error
        vm.expectRevert(
            abi.encodeWithSelector(WerkRegistrar.LabelAlreadyTaken.selector, keccak256(bytes("alice")), address(space))
        );

        // Run the test
        space2.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.reserve, ("alice")));
    }

    function test_RevertWhen_CallerIsEOA() external {
        // Compute an unauthorized address
        address unauthorized = makeAddr("unauthorized");

        // Make the unauthorized address the caller
        vm.prank(unauthorized);

        // Expect the next call to revert with the {SpaceZeroCodeSize} error
        vm.expectRevert(WerkRegistrar.SpaceZeroCodeSize.selector);

        // Run the test
        werkRegistrar.reserve("alice");
    }

    function test_RevertWhen_CallerNotSpace() external {
        // Initialize a non compliant space
        MockNonCompliantSpace nonCompliant = new MockNonCompliantSpace(users.admin);

        // Expect the next call to revert with the {SpaceUnsupportedInterface} error
        vm.expectRevert(WerkRegistrar.SpaceUnsupportedInterface.selector);

        // Run the test
        nonCompliant.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.reserve, ("alice")));
    }

    function test_RevertWhen_LabelEmpty() external {
        _expectInvalidLabelOnReserve("");
    }

    function test_RevertWhen_LabelTooShort() external {
        _expectInvalidLabelOnReserve("ab");
    }

    function test_RevertWhen_LabelTooLong() external {
        // 64 characters, one above `MAX_LABEL_LENGTH`
        _expectInvalidLabelOnReserve("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    }

    function test_RevertWhen_LabelHasUppercase() external {
        _expectInvalidLabelOnReserve("Alice");
    }

    function test_RevertWhen_LabelHasDot() external {
        _expectInvalidLabelOnReserve("al.ice");
    }

    function test_RevertWhen_LabelHasNonASCII() external {
        _expectInvalidLabelOnReserve(unicode"café");
    }

    function test_RevertWhen_LabelStartsWithHyphen() external {
        _expectInvalidLabelOnReserve("-alice");
    }

    function test_RevertWhen_LabelEndsWithHyphen() external {
        _expectInvalidLabelOnReserve("alice-");
    }

    function test_RevertWhen_LabelHasHyphensAtThirdAndFourthPositions() external {
        _expectInvalidLabelOnReserve("xn--alice");
    }

    function test_RevertWhen_RegisterInvalidLabel() external {
        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {InvalidLabel} error before any reservation check
        vm.expectRevert(abi.encodeWithSelector(WerkRegistrar.InvalidLabel.selector, "Alice"));

        // Run the test
        space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.register, ("Alice")));
    }

    function test_ClaimSubname_LabelWithDigitsAndHyphens() external {
        string memory label = "acme-co-2026";

        // Alice reserves and registers a label with digits and inner hyphens
        _reserveAndRegisterSubname(space, users.alice, label);

        // Assert that it resolves to the space
        assertEq(_resolveAddr(label), address(space), "label with digits and hyphens should resolve to space");
    }

    function test_ClaimSubname_LabelMaxLength() external {
        // 63 characters, exactly `MAX_LABEL_LENGTH`
        string memory label = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

        // Alice reserves and registers the longest allowed label
        _reserveAndRegisterSubname(space, users.alice, label);

        // Assert that it resolves to the space
        assertEq(_resolveAddr(label), address(space), "max length label should resolve to space");
    }

    function test_Available_InvalidLabel() external view {
        // Assert that an invalid label is reported as unavailable
        assertFalse(werkRegistrar.available("Alice"), "invalid label should not be available");
    }

    function test_RevertWhen_NoReservation() external {
        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {ReservationNotFound} error
        vm.expectRevert(WerkRegistrar.ReservationNotFound.selector);

        // Run the test
        space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.register, ("alice")));
    }

    function test_RevertWhen_ReservationExpired() external {
        // Alice reserves a subname
        _reserveSubname(space, users.alice, "alice");

        // Warp past the 30-minute reservation window
        vm.warp(block.timestamp + 31 minutes);

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {ReservationExpired} error
        vm.expectRevert(WerkRegistrar.ReservationExpired.selector);
        space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.register, ("alice")));
    }

    function test_RevertWhen_NotReservationOwner() external {
        // space reserves "alice"
        _reserveSubname(space, users.alice, "alice");

        // space2 tries to claim it
        vm.prank(users.bob);

        // Expect the next call to revert with the {ReservationNotFound} error
        vm.expectRevert(
            abi.encodeWithSelector(WerkRegistrar.NotReservationOwner.selector, block.timestamp + 30 minutes)
        );

        // Run the test
        space2.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.register, ("alice")));
    }

    function test_RevertWhen_AlreadyReserved() external {
        // Alice reserves subname
        _reserveSubname(space, users.alice, "alice");

        // Make Bob the caller
        vm.prank(users.bob);

        // Expect the next call to revert with the {AlreadyReserved} error
        vm.expectRevert(abi.encodeWithSelector(WerkRegistrar.AlreadyReserved.selector, block.timestamp + 30 minutes));

        // Run the test
        space2.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.reserve, ("alice")));
    }

    function test_RevertWhen_SpaceUnregistersSubname() external {
        // Alice reserves and registers subname
        _reserveAndRegisterSubname(space, users.alice, "alice");

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
        // Alice reserves and registers subname
        _reserveAndRegisterSubname(space, users.alice, "alice");

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
        // Alice reserves and registers subname
        _reserveAndRegisterSubname(space, users.alice, "alice");

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
        _reserveAndRegisterSubname(space, users.alice, "alice");
        _reserveAndRegisterSubname(space2, users.bob, "bob");

        // Assert they resolve correctly
        assertEq(_resolveAddr("alice"), address(space), "alice should resolve to space");
        assertEq(_resolveAddr("bob"), address(space2), "bob should resolve to space2");
    }

    function test_Available() external {
        // Assert that unclaimed label is available
        assertTrue(werkRegistrar.available("alice"), "unclaimed label should be available");

        // Assert that reserved label is not available
        _reserveSubname(space, users.alice, "alice");
        assertFalse(werkRegistrar.available("alice"), "reserved label should not be available");

        // Assert that expired reservation makes label available again
        vm.warp(block.timestamp + 31 minutes);
        assertTrue(werkRegistrar.available("alice"), "expired reservation should be available");

        // Assert that claimed label is not available
        // Note: claimed by another space as the first one is still in its reservation cooldown
        _reserveAndRegisterSubname(space2, users.bob, "alice");
        assertFalse(werkRegistrar.available("alice"), "claimed label should not be available");
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  RESERVATION RULES
    //////////////////////////////////////////////////////////////////////////*/

    function test_Reserve_ReleasesPreviousReservation() external {
        // Alice reserves "alice"
        _reserveSubname(space, users.alice, "alice");

        // Alice reserves "bob", which releases her reservation of "alice"
        _reserveSubname(space, users.alice, "bob");

        // Assert that "alice" is available again while "bob" is reserved
        assertTrue(werkRegistrar.available("alice"), "released label should be available");
        assertFalse(werkRegistrar.available("bob"), "new reservation should not be available");

        // Assert that another space can reserve and register the released label right away
        _reserveAndRegisterSubname(space2, users.bob, "alice");
        assertEq(_resolveAddr("alice"), address(space2), "released label should resolve to space2");
    }

    function test_RevertWhen_ReserveDuringCooldown() external {
        // Alice reserves "alice" and lets the reservation expire
        _reserveSubname(space, users.alice, "alice");
        uint256 cooldownEnd = block.timestamp + 60 minutes;
        vm.warp(block.timestamp + 31 minutes);

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {ReservationCooldown} error
        vm.expectRevert(abi.encodeWithSelector(WerkRegistrar.ReservationCooldown.selector, cooldownEnd));

        // Run the test
        space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.reserve, ("alice")));
    }

    function test_RevertWhen_ReserveReleasedLabelDuringCooldown() external {
        // Alice reserves "alice", then releases it by reserving "bob"
        _reserveSubname(space, users.alice, "alice");
        _reserveSubname(space, users.alice, "bob");

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {ReservationCooldown} error as the release starts the cooldown
        vm.expectRevert(
            abi.encodeWithSelector(WerkRegistrar.ReservationCooldown.selector, block.timestamp + 30 minutes)
        );

        // Run the test
        space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.reserve, ("alice")));
    }

    function test_Reserve_AfterCooldown() external {
        // Alice reserves "alice" and waits for both the reservation and its cooldown to end
        _reserveSubname(space, users.alice, "alice");
        vm.warp(block.timestamp + 60 minutes);

        // Run the test
        _reserveSubname(space, users.alice, "alice");

        // Assert that the label is reserved again
        assertFalse(werkRegistrar.available("alice"), "label should be reserved again");
    }

    function test_RevertWhen_CallerNotRegisteredSpace() external {
        // Deploy a contract claiming to be a space without being registered on the {StationRegistry}
        MockUnregisteredSpace unregistered = new MockUnregisteredSpace();

        // Expect the next call to revert with the {SpaceNotRegistered} error
        vm.expectRevert(WerkRegistrar.SpaceNotRegistered.selector);

        // Run the test
        unregistered.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.reserve, ("alice")));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 EXPIRY & RENEWAL
    //////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_RenewBeforeGracePeriod() external {
        // Alice reserves and registers a subname
        _reserveAndRegisterSubname(space, users.alice, "alice");

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {RenewalNotOpen} error until the end of the first year
        vm.expectRevert(abi.encodeWithSelector(WerkRegistrar.RenewalNotOpen.selector, block.timestamp + 365 days));

        // Run the test
        space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.renew, ("alice")));
    }

    function test_Renew_DuringGracePeriod() external {
        // Alice reserves and registers a subname
        _reserveAndRegisterSubname(space, users.alice, "alice");
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
        // Alice reserves and registers a subname
        _reserveAndRegisterSubname(space, users.alice, "alice");

        // Warp into the grace period
        vm.warp(block.timestamp + 365 days + 1);

        // Make Bob the caller
        vm.prank(users.bob);

        // Expect the next call to revert with the {NotSubnameOwner} error
        vm.expectRevert(abi.encodeWithSelector(WerkRegistrar.NotSubnameOwner.selector, address(space2)));

        // Run the test
        space2.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.renew, ("alice")));
    }

    function test_RevertWhen_ReserveDuringGracePeriod() external {
        // Alice reserves and registers a subname
        _reserveAndRegisterSubname(space, users.alice, "alice");

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
        space2.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.reserve, ("alice")));
    }

    function test_RevertWhen_RenewAfterExpiry() external {
        // Alice reserves and registers a subname
        _reserveAndRegisterSubname(space, users.alice, "alice");

        // Warp past the grace period
        vm.warp(block.timestamp + 395 days);

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {NotSubnameOwner} error as the subname has expired
        vm.expectRevert(abi.encodeWithSelector(WerkRegistrar.NotSubnameOwner.selector, address(space)));

        // Run the test
        space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.renew, ("alice")));
    }

    function test_ClaimExpiredLabel_ByAnotherSpace() external {
        // Alice reserves and registers a subname, then lets it expire
        _reserveAndRegisterSubname(space, users.alice, "alice");
        vm.warp(block.timestamp + 395 days);

        // Run the test
        _reserveAndRegisterSubname(space2, users.bob, "alice");

        // Assert that the label now resolves to the new space and the previous space has no active subname
        assertEq(_resolveAddr("alice"), address(space2), "expired label should resolve to the new space");
        assertEq(werkRegistrar.getSpaceForLabel("alice"), address(space2), "space for label mismatch");
        assertEq(werkRegistrar.getLabelHashForSpace(address(space)), bytes32(0), "previous space should be freed");
    }

    function test_ClaimNewLabel_AfterOwnSubnameExpired() external {
        // Alice reserves and registers a subname, then lets it expire
        _reserveAndRegisterSubname(space, users.alice, "alice");
        vm.warp(block.timestamp + 395 days);

        // Run the test
        _reserveAndRegisterSubname(space, users.alice, "alice-new");

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
        _reserveAndRegisterSubname(space, users.alice, "alice");
        _reserveAndRegisterSubname(space2, users.bob, "bob");

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
        _reserveAndRegisterSubname(space, users.alice, "alice-new");
        assertEq(_resolveAddr("alice-new"), address(space), "new subname should resolve to space");
    }

    function test_RevertWhen_ClearLabelsCallerNotOwner() external {
        // Alice reserves and registers a subname
        _reserveAndRegisterSubname(space, users.alice, "alice");

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
        // Alice reserves and registers a subname
        _reserveAndRegisterSubname(space, users.alice, "alice");

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
        assertEq(
            werkRegistrar.getLabelHashForSpace(address(space)), keccak256(bytes("alice")), "label for space mismatch"
        );

        // Assert that the space still cannot reserve a second subname after the upgrade
        vm.prank(users.alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                WerkRegistrar.SpaceAlreadyHasSubname.selector, address(space), keccak256(bytes("alice"))
            )
        );
        space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.reserve, ("bob")));
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
        implementation.initialize(werkRegistry, werkResolver, ISpaceFactory(address(stationRegistry)), users.eve);
    }

    function test_RevertWhen_ReinitializeProxy() external {
        // Expect the next call to revert with the {InvalidInitialization} error
        vm.expectRevert(Initializable.InvalidInitialization.selector);

        // Run the test
        werkRegistrar.initialize(werkRegistry, werkResolver, ISpaceFactory(address(stationRegistry)), users.eve);
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

    function _reserveSubname(Space _space, address caller, string memory label) internal {
        vm.prank(caller);
        _space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.reserve, (label)));
    }

    function _claimSubname(Space _space, address caller, string memory label) internal {
        vm.prank(caller);
        _space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.register, (label)));
    }

    function _reserveAndRegisterSubname(Space _space, address caller, string memory label) internal {
        _reserveSubname(_space, caller, label);
        _claimSubname(_space, caller, label);
    }

    function _renewSubname(Space _space, address caller, string memory label) internal {
        vm.prank(caller);
        _space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.renew, (label)));
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

    /// @dev Expects reserving `label` from the space to revert with the {InvalidLabel} error
    function _expectInvalidLabelOnReserve(string memory label) internal {
        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {InvalidLabel} error
        vm.expectRevert(abi.encodeWithSelector(WerkRegistrar.InvalidLabel.selector, label));

        // Run the test
        space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.reserve, (label)));
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
