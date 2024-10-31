// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Events } from "./utils/Events.sol";
import { Users } from "./utils/Types.sol";
import { Test } from "forge-std/Test.sol";
import { MockERC20NoReturn } from "./mocks/MockERC20NoReturn.sol";
import { MockNonCompliantWorkspace } from "./mocks/MockNonCompliantWorkspace.sol";
import { MockModule } from "./mocks/MockModule.sol";
import { MockBadReceiver } from "./mocks/MockBadReceiver.sol";
import { Space } from "./../src/Space.sol";
import { ModuleKeeper } from "./../src/ModuleKeeper.sol";
import { DockRegistry } from "./../src/DockRegistry.sol";
import { EntryPoint } from "@thirdweb/contracts/prebuilts/account/utils/Entrypoint.sol";
import { MockERC721Collection } from "./mocks/MockERC721Collection.sol";
import { MockERC1155Collection } from "./mocks/MockERC1155Collection.sol";
import { MockBadSpace } from "./mocks/MockBadSpace.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

abstract contract Base_Test is Test, Events {
    /*//////////////////////////////////////////////////////////////////////////
                                     VARIABLES
    //////////////////////////////////////////////////////////////////////////*/

    Users internal users;

    /*//////////////////////////////////////////////////////////////////////////
                                   TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    EntryPoint internal entrypoint;
    DockRegistry internal dockRegistry;
    Space internal space;
    ModuleKeeper internal moduleKeeper;
    MockERC20NoReturn internal usdt;
    MockModule internal mockModule;
    MockNonCompliantWorkspace internal mockNonCompliantWorkspace;
    MockBadReceiver internal mockBadReceiver;
    MockERC721Collection internal mockERC721;
    MockERC1155Collection internal mockERC1155;

    /*//////////////////////////////////////////////////////////////////////////
                                   TEST STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    address[] internal mockModules;
    address internal containerImplementation;

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        // Deploy the mock USDT contract to deal it to the users
        usdt = new MockERC20NoReturn("Tether USD", "USDT", 6);

        // Create test users
        users = Users({ admin: createUser("admin"), eve: createUser("eve"), bob: createUser("bob") });

        // Deploy test contracts
        entrypoint = new EntryPoint();
        moduleKeeper = new ModuleKeeper({ _initialOwner: users.admin });

        dockRegistry = new DockRegistry(users.admin, entrypoint, moduleKeeper);
        containerImplementation = address(new Space(entrypoint, address(dockRegistry)));

        mockModule = new MockModule();
        mockNonCompliantWorkspace = new MockNonCompliantWorkspace({ _owner: users.admin });
        mockBadReceiver = new MockBadReceiver();
        mockERC721 = new MockERC721Collection("MockERC721Collection", "MC");
        mockERC1155 = new MockERC1155Collection("https://nft.com/0x1.json");

        // Create a mock modules array
        mockModules.push(address(mockModule));

        // Label the test contracts so we can easily track them
        vm.label({ account: address(dockRegistry), newLabel: "DockRegistry" });
        vm.label({ account: address(entrypoint), newLabel: "EntryPoint" });
        vm.label({ account: address(moduleKeeper), newLabel: "ModuleKeeper" });
        vm.label({ account: address(usdt), newLabel: "USDT" });
        vm.label({ account: address(mockModule), newLabel: "MockModule" });
        vm.label({ account: address(mockNonCompliantWorkspace), newLabel: "MockNonCompliantWorkspace" });
    }

    /*//////////////////////////////////////////////////////////////////////////
                            DEPLOYMENT-RELATED FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Deploys a new {Space} smart account based on the provided `owner`, `moduleKeeper` and `initialModules` input params
    function deploySpace(
        address _owner,
        uint256 _spaceId,
        address[] memory _initialModules
    ) internal returns (Space _container) {
        vm.startPrank({ msgSender: users.admin });
        for (uint256 i; i < _initialModules.length; ++i) {
            allowlistModule(_initialModules[i]);
        }
        vm.stopPrank();

        bytes memory data =
            computeCreateAccountCalldata({ deployer: _owner, dockId: _spaceId, initialModules: _initialModules });

        vm.prank({ msgSender: _owner });
        _container = Space(payable(dockRegistry.createAccount({ _admin: _owner, _data: data })));
        vm.stopPrank();
    }

    /// @dev Deploys a new {MockBadSpace} smart account based on the provided `owner`, `moduleKeeper` and `initialModules` input params
    function deployBadWorkspace(
        address _owner,
        uint256 _spaceId,
        address[] memory _initialModules
    ) internal returns (MockBadSpace _badWorkspace) {
        vm.startPrank({ msgSender: users.admin });
        for (uint256 i; i < _initialModules.length; ++i) {
            allowlistModule(_initialModules[i]);
        }
        vm.stopPrank();

        bytes memory data =
            computeCreateAccountCalldata({ deployer: _owner, dockId: _spaceId, initialModules: _initialModules });

        vm.prank({ msgSender: _owner });
        _badWorkspace = MockBadSpace(payable(dockRegistry.createAccount({ _admin: _owner, _data: data })));
        vm.stopPrank();
    }

    function allowlistModule(address _module) internal {
        moduleKeeper.addToAllowlist({ module: _module });
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    OTHER HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Generates a user, labels its address, and funds it with test assets
    function createUser(string memory name) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        vm.deal({ account: user, newBalance: 100 ether });
        deal({ token: address(usdt), to: user, give: 10_000_000e18 });

        return user;
    }

    /// @dev Predicts the address of the next contract that is going to be deployed by the `deployer`
    /// and constructs the calldata to be used to create the new smart account
    function computeDeploymentAddressAndCalldata(
        address deployer,
        uint256 dockId,
        address[] memory initialModules
    ) internal view returns (address expectedAddress, bytes memory data) {
        data = computeCreateAccountCalldata(deployer, dockId, initialModules);

        // Compute the final salt made by the deployer address and initialization data
        bytes32 salt = keccak256(abi.encode(deployer, data));

        // Use {Clones} library to predict the smart account address based on the smart account implementation, salt and account factory
        expectedAddress =
            Clones.predictDeterministicAddress(dockRegistry.accountImplementation(), salt, address(dockRegistry));
    }

    /// @dev Constructs the calldata passed to the {DockRegistry}.createAccount method
    function computeCreateAccountCalldata(
        address deployer,
        uint256 dockId,
        address[] memory initialModules
    ) internal view returns (bytes memory data) {
        // Get the total account deployed by `deployer` and use it as a unique salt field
        // because a signer must be able to deploy multiple smart accounts within one
        // dock with the same initial modules
        uint256 totalAccountsOfDeployer = dockRegistry.totalAccountsOfSigner(deployer);

        // Construct the calldata to be used to initialize the {Space} smart account
        data = abi.encode(totalAccountsOfDeployer, dockId, initialModules);
    }
}
