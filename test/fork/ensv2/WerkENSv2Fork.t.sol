// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Space } from "src/Space.sol";
import { MockNonCompliantSpace } from "../../mocks/MockNonCompliantSpace.sol";
import { WerkRegistrar } from "src/peripherals/ensv2/WerkRegistrar.sol";
import { IVerifiableFactory } from "src/peripherals/ensv2/interfaces/IVerifiableFactory.sol";
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

        // Step 4: Deploy WerkRegistrar
        werkRegistrar = new WerkRegistrar(werkRegistry, werkResolver, users.admin);
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

        // Verify mappings on the registrar
        bytes32 labelHash = keccak256(bytes(label));
        assertEq(werkRegistrar.labelToSpace(labelHash), address(space), "labelToSpace mismatch");
        assertEq(werkRegistrar.spaceToLabel(address(space)), labelHash, "spaceToLabel mismatch");

        // Verify the name is registered in the Werk registry
        assertEq(werkRegistry.getResolver(label), werkResolver, "resolver mismatch");

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

        // Alice reserves a second subname
        _reserveSubname(space, users.alice, "bob");

        // Make alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {SpaceAlreadyHasSubname} error
        vm.expectRevert(
            abi.encodeWithSelector(
                WerkRegistrar.SpaceAlreadyHasSubname.selector, address(space), keccak256(bytes("alice"))
            )
        );

        // Run the test
        space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.register, ("bob")));
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

    function test_AddCoinType() external {
        // Alice reserves and registers subname
        _reserveAndRegisterSubname(space, users.alice, "alice");

        // Assert that no explicit Optimism record exists yet as it only resolves via the default record
        assertFalse(_hasAddress("alice", Constants.OPTIMISM_COIN_TYPE), "Optimism record should not exist yet");

        // Make Alice the caller
        vm.prank(users.alice);

        // Run the test
        space.execute(
            address(werkRegistrar),
            0,
            abi.encodeCall(WerkRegistrar.addCoinType, ("alice", Constants.OPTIMISM_COIN_TYPE))
        );

        // Assert that the explicit Optimism record was set to the space address
        assertTrue(_hasAddress("alice", Constants.OPTIMISM_COIN_TYPE), "Optimism record should exist");
        bytes memory optimismAddr = _resolveAddress("alice", Constants.OPTIMISM_COIN_TYPE);
        assertEq(optimismAddr, abi.encodePacked(address(space)), "Optimism address mismatch");
    }

    function test_RevertWhen_CoinTypeNotEVM() external {
        // Alice reserves and registers subname
        _reserveAndRegisterSubname(space, users.alice, "alice");

        // Make Alice the caller
        vm.prank(users.alice);

        // Expect the next call to revert with the {InvalidCoinType} error
        vm.expectRevert(abi.encodeWithSelector(WerkRegistrar.InvalidCoinType.selector, Constants.SOLANA_COIN_TYPE));

        // Run the test
        space.execute(
            address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.addCoinType, ("alice", Constants.SOLANA_COIN_TYPE))
        );
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
        _reserveSubname(space, users.alice, "alice");
        _claimSubname(space, users.alice, "alice");
        assertFalse(werkRegistrar.available("alice"), "claimed label should not be available");
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

    /// @dev Checks through the public Universal Resolver whether `<label>.werk.eth` has an explicit `coinType` record
    function _hasAddress(string memory label, uint256 coinType) internal view returns (bool) {
        bytes32 node = keccak256(abi.encodePacked(werkNode, keccak256(bytes(label))));
        bytes memory data = abi.encodeWithSignature("hasAddr(bytes32,uint256)", node, coinType);

        (bytes memory result,) = IUniversalResolver(Constants.UNIVERSAL_RESOLVER).resolve(_dnsEncode(label), data);

        return abi.decode(result, (bool));
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
