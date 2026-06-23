// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Space } from "src/Space.sol";
import { MockNonCompliantSpace } from "../../mocks/MockNonCompliantSpace.sol";
import { WerkRegistry } from "src/peripherals/ensv2/WerkRegistry.sol";
import { WerkRegistrar } from "src/peripherals/ensv2/WerkRegistrar.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IPermissionedRegistry } from "@ensv2/registry/interfaces/IPermissionedRegistry.sol";
import { RegistryRolesLib } from "@ensv2/registry/libraries/RegistryRolesLib.sol";
import { IHCAFactoryBasic } from "@ensv2/hca/interfaces/IHCAFactoryBasic.sol";
import { IRegistryMetadata } from "@ensv2/registry/interfaces/IRegistryMetadata.sol";
import { IStandardRegistry } from "@ensv2/registry/interfaces/IStandardRegistry.sol";
import { IRegistry } from "@ensv2/registry/interfaces/IRegistry.sol";
import { Constants } from "../../utils/Constants.sol";
import { Fork_Test } from "../../fork/Fork.t.sol";

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
contract WerkENSv2Fork_Test is Fork_Test {
    /*//////////////////////////////////////////////////////////////////////////
                                     VARIABLES
    //////////////////////////////////////////////////////////////////////////*/

    WerkRegistry werkRegistry;
    WerkRegistrar werkRegistrar;
    IResolver resolver;

    bytes32 ethNode;
    bytes32 werkNode;

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public override {
        Fork_Test.setUp();

        // Compute ENS nodes
        ethNode = keccak256(abi.encodePacked(bytes32(0), keccak256("eth")));
        werkNode = keccak256(abi.encodePacked(ethNode, keccak256("werk")));

        // Step 1: Deploy a PermissionedResolver
        resolver = deployWerkResolver();
        vm.label(address(resolver), "WerkResolver");

        // Step 2: Deploy WerkRegistry
        werkRegistry = deployWerkRegistry();
        vm.label(address(werkRegistry), "WerkRegistry");

        // Step 3: Register "werk.eth" on the ETH registry
        // Note: On testnet/mainnet "werk.eth" will already be registered
        registerWerkLabel();

        // Step 4: Deploy WerkRegistrar
        werkRegistrar =
            new WerkRegistrar(IPermissionedRegistry(address(werkRegistry)), address(resolver), Constants.WERK_OWNER);
        vm.label(address(werkRegistrar), "WerkRegistrar");

        // Step 5: Grant ROLE_REGISTRAR to WerkRegistrar on WerkRegistry
        vm.prank(Constants.WERK_OWNER);
        werkRegistry.grantRootRoles(RegistryRolesLib.ROLE_REGISTRAR, address(werkRegistrar));

        // Step 6: Grant resolver write permissions to WerkRegistrar
        vm.prank(Constants.WERK_OWNER);
        uint256 ROLE_SET_ADDR = 1 << 0;
        uint256 ROLE_SET_ADDR_ADMIN = ROLE_SET_ADDR << 128;
        resolver.grantRootRoles(ROLE_SET_ADDR | ROLE_SET_ADDR_ADMIN, address(werkRegistrar));

        // Step 7: Allowlist WerkRegistrar in ModuleKeeper so Spaces can call it
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

        // Verify the name is registered in WerkRegistry
        bytes32 aliceNode = keccak256(abi.encodePacked(werkNode, labelHash));

        // Verify ENSIP-19 default record was set
        bytes memory defaultAddrBytes = resolver.addr(aliceNode, Constants.COIN_TYPE_DEFAULT);
        assertEq(defaultAddrBytes, abi.encodePacked(address(space)), "default address mismatch");

        // ETH (coinType 60) resolves via default
        address resolvedAddr = resolver.addr(aliceNode);
        assertEq(resolvedAddr, address(space), "ETH fallback mismatch");

        // Base resolves via default (fallback)
        bytes memory baseAddrBytes = resolver.addr(aliceNode, Constants.BASE_COIN_TYPE);
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

    function test_RevertWhen_EmptyLabel() external {
        vm.prank(users.alice);
        vm.expectRevert(WerkRegistrar.EmptyLabel.selector);
        space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.reserve, ("")));
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
        vm.expectRevert(abi.encodeWithSelector(WerkRegistrar.NotReservationOwner.selector, block.timestamp + 30 minutes));

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

        // Add an additional coin type (e.g., Solana coinType = 501)
        uint256 solanaCoinType = 501;
        vm.prank(users.alice);
        space.execute(address(werkRegistrar), 0, abi.encodeCall(WerkRegistrar.addCoinType, ("alice", solanaCoinType)));

        // Verify the new coin type record
        bytes32 labelHash = keccak256(bytes("alice"));
        bytes32 aliceNode = keccak256(abi.encodePacked(werkNode, labelHash));
        bytes memory solanaAddr = resolver.addr(aliceNode, solanaCoinType);
        assertEq(solanaAddr, abi.encodePacked(address(space)), "Solana address mismatch");
    }

    function test_MultipleSpaces_ClaimDifferentSubnames() external {
        // Alice and Bob each claim a subname
        _reserveAndRegisterSubname(space, users.alice, "alice");
        _reserveAndRegisterSubname(space2, users.bob, "bob");

        // Compute nodes for both alice and bob
        bytes32 aliceNode = keccak256(abi.encodePacked(werkNode, keccak256(bytes("alice"))));
        bytes32 bobNode = keccak256(abi.encodePacked(werkNode, keccak256(bytes("bob"))));

        // Assert they resolve correctly
        assertEq(resolver.addr(aliceNode), address(space), "alice should resolve to space");
        assertEq(resolver.addr(bobNode), address(space2), "bob should resolve to space2");
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

    /// @dev Deploys a PermissionedResolver proxy for Werk subnames
    function deployWerkResolver() internal returns (IResolver) {
        uint256 ROLE_SET_ADDR = 1 << 0;
        uint256 ROLE_SET_ADDR_ADMIN = ROLE_SET_ADDR << 128;
        uint256 resolverOwnerRoles = ROLE_SET_ADDR | ROLE_SET_ADDR_ADMIN;

        bytes memory resolverInitData = abi.encodeCall(IResolver.initialize, (Constants.WERK_OWNER, resolverOwnerRoles));
        return IResolver(address(new ERC1967Proxy(Constants.PERMISSIONED_RESOLVER_IMPL, resolverInitData)));
    }

    /// @dev Deploys the WerkRegistry
    function deployWerkRegistry() internal returns (WerkRegistry) {
        uint256 ownerRoles = RegistryRolesLib.ROLE_REGISTRAR_ADMIN | RegistryRolesLib.ROLE_REGISTRAR
            | RegistryRolesLib.ROLE_SET_RESOLVER | RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN
            | RegistryRolesLib.ROLE_SET_PARENT | RegistryRolesLib.ROLE_SET_PARENT_ADMIN
            | RegistryRolesLib.ROLE_UNREGISTER | RegistryRolesLib.ROLE_UNREGISTER_ADMIN | RegistryRolesLib.ROLE_RENEW
            | RegistryRolesLib.ROLE_RENEW_ADMIN;

        return new WerkRegistry(
            IHCAFactoryBasic(Constants.HCA_FACTORY),
            IRegistryMetadata(Constants.SIMPLE_REGISTRY_METADATA),
            Constants.WERK_OWNER,
            ownerRoles
        );
    }

    /// @dev Registers "werk" label on the ETH registry
    function registerWerkLabel() internal {
        uint256 werkRoles = RegistryRolesLib.ROLE_SET_RESOLVER | RegistryRolesLib.ROLE_RENEW
            | RegistryRolesLib.ROLE_UNREGISTER | RegistryRolesLib.ROLE_SET_SUBREGISTRY
            | RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;

        vm.prank(Constants.ETH_REGISTRAR);
        IStandardRegistry(Constants.ETH_REGISTRY)
            .register(
                "werk",
                Constants.WERK_OWNER,
                IRegistry(address(werkRegistry)),
                address(resolver),
                werkRoles,
                type(uint64).max
            );
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
}
