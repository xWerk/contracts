// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Space } from "src/Space.sol";
import { StationRegistry } from "src/StationRegistry.sol";
import { ModuleKeeper } from "src/ModuleKeeper.sol";
import { WerkRegistry } from "src/peripherals/ensv2/WerkRegistry.sol";
import { WerkRegistrar } from "src/peripherals/ensv2/WerkRegistrar.sol";
import { IEntryPoint } from "@thirdweb/contracts/prebuilts/account/interface/IEntrypoint.sol";
import { IHCAFactoryBasic } from "@ensv2/hca/interfaces/IHCAFactoryBasic.sol";
import { IRegistryMetadata } from "@ensv2/registry/interfaces/IRegistryMetadata.sol";
import { IPermissionedRegistry } from "@ensv2/registry/interfaces/IPermissionedRegistry.sol";
import { IRegistry } from "@ensv2/registry/interfaces/IRegistry.sol";
import { IStandardRegistry } from "@ensv2/registry/interfaces/IStandardRegistry.sol";
import { RegistryRolesLib } from "@ensv2/registry/libraries/RegistryRolesLib.sol";

/// @notice Minimal interface to read address records from the ENSv2 PermissionedResolver.
interface IResolver {
    function addr(bytes32 node) external view returns (address payable);
    function addr(bytes32 node, uint256 coinType) external view returns (bytes memory);
    function setAddr(bytes32 node, uint256 coinType, bytes calldata value) external;
    function initialize(address admin, uint256 roleBitmap) external;
    function grantRootRoles(uint256 roleBitmap, address account) external returns (bool);
}

/// @notice Fork test against local anvil running ENSv2 devnet.
/// Tests the full subname registration and resolution flow.
contract WerkENSv2Fork_Test is Test {
    // Addresses of the ENSv2 contracts deployed on anvil
    IHCAFactoryBasic constant HCA_FACTORY = IHCAFactoryBasic(0x0165878A594ca255338adfa4d48449f69242Eb8F);
    IRegistryMetadata constant SIMPLE_REGISTRY_METADATA = IRegistryMetadata(0xa513E6E4b8f2a923D98304ec87F64353C4D5C853);
    IStandardRegistry constant ETH_REGISTRY = IStandardRegistry(0x9E545E3C0baAB3E08CdfD552C960A1050f373042);

    // PermissionedResolverImpl deployed on anvil
    address constant PERMISSIONED_RESOLVER_IMPL = 0x1613beB3B2C4f22Ee086B2b38C1476A3cE7f78E8;

    // ENSv2 devnet named accounts
    address constant OWNER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address constant WERK_OWNER = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;

    // ENSIP-19 default coin type and Base-specific coin type for resolution tests
    // Note: only use `BASE_COIN_TYPE` to test that it fallbacks to `COIN_TYPE_DEFAULT`
    uint256 constant COIN_TYPE_DEFAULT = 1 << 31;
    uint256 constant BASE_COIN_TYPE = 2_147_492_101;

    // Werk infrastructure contracts
    StationRegistry stationRegistry;
    ModuleKeeper moduleKeeper;

    // ENSv2 Werk contracts
    WerkRegistry werkRegistry;
    WerkRegistrar werkRegistrar;
    IResolver resolver;

    // Computed values
    bytes32 ethNode;
    bytes32 werkNode;

    // Test admin (owns the Spaces)
    address admin;

    // Test Spaces (Space deployments)
    Space space;
    Space space2;

    function setUp() public {
        admin = makeAddr("admin");
        vm.deal(admin, 100 ether);

        // Deploy Werk infrastructure: ModuleKeeper → StationRegistry → Spaces
        // ___________________________________________________________________

        moduleKeeper = new ModuleKeeper({ _initialOwner: admin });

        // Deploy StationRegistry
        StationRegistry registryImpl = new StationRegistry();
        bytes memory emptyData;
        ERC1967Proxy registryProxy = new ERC1967Proxy(address(registryImpl), emptyData);
        Space spaceImpl = new Space(IEntryPoint(address(0)), address(registryProxy));
        StationRegistry(address(registryProxy))
            .initialize(admin, IEntryPoint(address(0)), moduleKeeper, address(spaceImpl));
        stationRegistry = StationRegistry(address(registryProxy));

        // Deploy two Space instances
        space = _deploySpace(admin);
        vm.label(address(space), "werkSpace");
        vm.deal(address(space), 10 ether);

        space2 = _deploySpace(admin);
        vm.label(address(space2), "werkSpace2");
        vm.deal(address(space2), 10 ether);

        // Deploy ENSv2 Werk contracts
        // ___________________________________________________________________

        // Compute ENS nodes
        ethNode = keccak256(abi.encodePacked(bytes32(0), keccak256("eth")));
        werkNode = keccak256(abi.encodePacked(ethNode, keccak256("werk")));

        // Step 1: Deploy a PermissionedResolver proxy for Werk subnames
        uint256 ROLE_SET_ADDR = 1 << 0;
        uint256 ROLE_SET_ADDR_ADMIN = ROLE_SET_ADDR << 128;
        uint256 resolverOwnerRoles = ROLE_SET_ADDR | ROLE_SET_ADDR_ADMIN;

        bytes memory resolverInitData = abi.encodeCall(IResolver.initialize, (WERK_OWNER, resolverOwnerRoles));
        resolver = IResolver(address(new ERC1967Proxy(PERMISSIONED_RESOLVER_IMPL, resolverInitData)));
        vm.label(address(resolver), "WerkResolver");

        // Step 2: Deploy WerkRegistry
        uint256 ownerRoles = RegistryRolesLib.ROLE_REGISTRAR_ADMIN | RegistryRolesLib.ROLE_REGISTRAR
            | RegistryRolesLib.ROLE_SET_RESOLVER | RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN
            | RegistryRolesLib.ROLE_SET_PARENT | RegistryRolesLib.ROLE_SET_PARENT_ADMIN
            | RegistryRolesLib.ROLE_UNREGISTER | RegistryRolesLib.ROLE_UNREGISTER_ADMIN | RegistryRolesLib.ROLE_RENEW
            | RegistryRolesLib.ROLE_RENEW_ADMIN;

        werkRegistry = new WerkRegistry(HCA_FACTORY, SIMPLE_REGISTRY_METADATA, WERK_OWNER, ownerRoles);
        vm.label(address(werkRegistry), "WerkRegistry");

        // Step 3: Register "werk.eth" on the ETH registry
        // Note: On testnet/mainnet "werk.eth" will already be registered
        address ETH_REGISTRAR = 0x5f3f1dBD7B74C6B46e8c44f98792A1dAf8d69154;

        uint256 werkRoles = RegistryRolesLib.ROLE_SET_RESOLVER | RegistryRolesLib.ROLE_RENEW
            | RegistryRolesLib.ROLE_UNREGISTER | RegistryRolesLib.ROLE_SET_SUBREGISTRY
            | RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;

        vm.prank(ETH_REGISTRAR);
        ETH_REGISTRY.register(
            "werk", WERK_OWNER, IRegistry(address(werkRegistry)), address(resolver), werkRoles, type(uint64).max
        );

        // Step 4: Deploy WerkRegistrar
        werkRegistrar =
            new WerkRegistrar(IPermissionedRegistry(address(werkRegistry)), address(resolver), werkNode, WERK_OWNER);
        vm.label(address(werkRegistrar), "WerkRegistrar");

        // Step 5: Grant ROLE_REGISTRAR to WerkRegistrar on WerkRegistry
        vm.prank(WERK_OWNER);
        werkRegistry.grantRootRoles(RegistryRolesLib.ROLE_REGISTRAR, address(werkRegistrar));

        // Step 6: Grant resolver write permissions to WerkRegistrar
        vm.prank(WERK_OWNER);
        resolver.grantRootRoles(ROLE_SET_ADDR | ROLE_SET_ADDR_ADMIN, address(werkRegistrar));

        // Step 7: Allowlist WerkRegistrar in ModuleKeeper so Spaces can call it
        address[] memory modules = new address[](1);
        modules[0] = address(werkRegistrar);
        vm.prank(admin);
        moduleKeeper.addToAllowlist(modules);
    }

    /// @notice Test that space can claim "alice.werk.eth" and it resolves correctly.
    function test_ClaimSubname_And_Resolve() external {
        string memory label = "alice";

        // Step 1: Space reserves the label
        _reserveSubname(space, label);

        // Step 2: Space claims the subname
        _claimSubname(space, label);

        // Verify mappings on the registrar
        bytes32 labelHash = keccak256(bytes(label));
        assertEq(werkRegistrar.labelToSpace(labelHash), address(space), "labelToSpace mismatch");
        assertEq(werkRegistrar.spaceToLabel(address(space)), labelHash, "spaceToLabel mismatch");

        // Verify the name is registered in WerkRegistry
        bytes32 aliceNode = keccak256(abi.encodePacked(werkNode, labelHash));

        // Verify ENSIP-19 default record was set
        bytes memory defaultAddrBytes = resolver.addr(aliceNode, COIN_TYPE_DEFAULT);
        assertEq(defaultAddrBytes, abi.encodePacked(address(space)), "default address mismatch");

        // ETH (coinType 60) resolves via default
        address resolvedAddr = resolver.addr(aliceNode);
        assertEq(resolvedAddr, address(space), "ETH fallback mismatch");

        // Base resolves via default (fallback)
        bytes memory baseAddrBytes = resolver.addr(aliceNode, BASE_COIN_TYPE);
        assertEq(baseAddrBytes, abi.encodePacked(address(space)), "Base fallback mismatch");
    }

    /// @notice Test that a space cannot claim two subnames
    function test_RevertWhen_SpaceAlreadyHasSubname() external {
        _reserveAndClaimSubname(space, "alice");

        _reserveSubname(space, "bob");

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                WerkRegistrar.SpaceAlreadyHasSubname.selector, address(space), keccak256(bytes("alice"))
            )
        );
        space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.claimSubname, ("bob")));
    }

    /// @notice Test that a label cannot be reserved if already claimed by another space.
    function test_RevertWhen_LabelAlreadyTaken() external {
        _reserveAndClaimSubname(space, "alice");

        // space2 tries to reserve the already-claimed label
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(WerkRegistrar.LabelAlreadyTaken.selector, keccak256(bytes("alice")), address(space))
        );
        space2.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.reserve, ("alice")));
    }

    /// @notice Test that an EOA (zero code size) cannot claim a subname.
    function test_RevertWhen_CallerIsEOA() external {
        address attacker = makeAddr("attacker");

        // EOA reserves the label directly
        vm.prank(attacker);
        werkRegistrar.reserve("alice");

        // EOA tries to claim — should fail at onlySpace (zero code size)
        vm.prank(attacker);
        vm.expectRevert(WerkRegistrar.SpaceZeroCodeSize.selector);
        werkRegistrar.claimSubname("alice");
    }

    /// @notice Test that a contract not implementing ISpace is rejected.
    function test_RevertWhen_CallerNotSpace() external {
        // Deploy a contract that doesn't implement ISpace
        NonSpaceContract notASpace = new NonSpaceContract();

        notASpace.reserve(werkRegistrar, "alice");

        vm.expectRevert(WerkRegistrar.SpaceUnsupportedInterface.selector);
        notASpace.claimSubname(werkRegistrar, "alice");
    }

    /// @notice Test that empty labels are rejected.
    function test_RevertWhen_EmptyLabel() external {
        vm.expectRevert(WerkRegistrar.EmptyLabel.selector);
        werkRegistrar.reserve("");
    }

    /// @notice Test that claiming without a reservation reverts.
    function test_RevertWhen_NoReservation() external {
        vm.prank(admin);
        vm.expectRevert(WerkRegistrar.ReservationNotFound.selector);
        space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.claimSubname, ("alice")));
    }

    /// @notice Test that claiming with an expired reservation reverts.
    function test_RevertWhen_ReservationExpired() external {
        _reserveSubname(space, "alice");

        // Warp past the 30-minute reservation window
        vm.warp(block.timestamp + 31 minutes);

        vm.prank(admin);
        vm.expectRevert(WerkRegistrar.ReservationExpired.selector);
        space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.claimSubname, ("alice")));
    }

    /// @notice Test that a different space cannot claim someone else's reservation.
    function test_RevertWhen_NotReservationOwner() external {
        // space reserves "alice"
        _reserveSubname(space, "alice");

        // space2 tries to claim it
        vm.prank(admin);
        vm.expectRevert();
        space2.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.claimSubname, ("alice")));
    }

    /// @notice Test that a label cannot be reserved while an active reservation exists.
    function test_RevertWhen_AlreadyReserved() external {
        _reserveSubname(space, "alice");

        vm.prank(admin);
        vm.expectRevert();
        space2.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.reserve, ("alice")));
    }

    /// @notice Test the addCoinType flow after claiming a subname.
    function test_AddCoinType() external {
        _reserveAndClaimSubname(space, "alice");

        // Add an additional coin type (e.g., Solana coinType = 501)
        uint256 solanaCoinType = 501;
        vm.prank(admin);
        space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.addCoinType, ("alice", solanaCoinType)));

        // Verify the new coin type record
        bytes32 labelHash = keccak256(bytes("alice"));
        bytes32 aliceNode = keccak256(abi.encodePacked(werkNode, labelHash));
        bytes memory solanaAddr = resolver.addr(aliceNode, solanaCoinType);
        assertEq(solanaAddr, abi.encodePacked(address(space)), "Solana address mismatch");
    }

    /// @notice Test that multiple spaces can each claim their own unique subnames.
    function test_MultipleSpaces_ClaimDifferentSubnames() external {
        _reserveAndClaimSubname(space, "alice");
        _reserveAndClaimSubname(space2, "bob");

        // Verify both resolve correctly
        bytes32 aliceNode = keccak256(abi.encodePacked(werkNode, keccak256(bytes("alice"))));
        bytes32 bobNode = keccak256(abi.encodePacked(werkNode, keccak256(bytes("bob"))));

        assertEq(resolver.addr(aliceNode), address(space), "alice should resolve to space");
        assertEq(resolver.addr(bobNode), address(space2), "bob should resolve to space2");
    }

    /// @notice Test the full lifecycle of `available`: unclaimed → reserved → expired → claimed
    function test_Available() external {
        // Unclaimed label is available
        assertTrue(werkRegistrar.available("alice"), "unclaimed label should be available");

        // Reserved label is not available
        _reserveSubname(space, "alice");
        assertFalse(werkRegistrar.available("alice"), "reserved label should not be available");

        // Expired reservation makes label available again
        vm.warp(block.timestamp + 31 minutes);
        assertTrue(werkRegistrar.available("alice"), "expired reservation should be available");

        // Claimed label is not available
        _reserveSubname(space, "alice");
        _claimSubname(space, "alice");
        assertFalse(werkRegistrar.available("alice"), "claimed label should not be available");
    }

    // Helpers
    function _deploySpace(address _admin) internal returns (Space _space) {
        uint256 totalAccounts = stationRegistry.totalAccountsOfSigner(_admin);
        bytes memory data = abi.encode(totalAccounts);

        vm.prank(_admin);
        _space = Space(payable(stationRegistry.createAccount(_admin, data)));
    }

    function _reserveSubname(Space _space, string memory label) internal {
        vm.prank(admin);
        _space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.reserve, (label)));
    }

    function _claimSubname(Space _space, string memory label) internal {
        vm.prank(admin);
        _space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.claimSubname, (label)));
    }

    function _reserveAndClaimSubname(Space _space, string memory label) internal {
        _reserveSubname(_space, label);
        _claimSubname(_space, label);
    }
}

/// @notice A contract that implements IERC165 but NOT ISpace — used to test the onlySpace guard.
contract NonSpaceContract is IERC165 {
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }

    function reserve(WerkRegistrar registrar, string calldata label) external {
        registrar.reserve(label);
    }

    function claimSubname(WerkRegistrar registrar, string calldata label) external {
        registrar.claimSubname(label);
    }
}
