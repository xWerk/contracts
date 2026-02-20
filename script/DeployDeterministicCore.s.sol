// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { PaymentModule } from "src/modules/payment-module/PaymentModule.sol";
import { CompensationModule } from "src/modules/compensation-module/CompensationModule.sol";
import { StationRegistry } from "src/StationRegistry.sol";
import { ModuleKeeper } from "src/ModuleKeeper.sol";
import { ISablierLockup } from "@sablier/lockup/src/interfaces/ISablierLockup.sol";
import { ISablierFlow } from "@sablier/flow/src/interfaces/ISablierFlow.sol";
import { IEntryPoint } from "@thirdweb/contracts/prebuilts/account/interface/IEntrypoint.sol";
import { CREATE3 } from "solady/src/utils/CREATE3.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Space } from "src/Space.sol";

/// @notice Deploys the Werk Protocol core contracts deterministically across all supported EVM chains
/// @dev Reverts if any contract has already been deployed
contract DeployDeterministicCore is BaseScript {
    address[] modules;

    /// @dev Uses `CREATE3` to ensure the same deployment addresses across chains
    /// Notes:
    /// - Each deployment uses a unique salt derived from its contract name via `create3Salt`
    function run(
        string memory createSalt
    )
        public
        virtual
        broadcast
        returns (
            ModuleKeeper moduleKeeper,
            StationRegistry stationRegistry,
            PaymentModule paymentModule,
            CompensationModule compensationModule
        )
    {
        moduleKeeper = _deployModuleKeeper(createSalt);
        stationRegistry = _deployStationRegistry(createSalt, moduleKeeper);
        paymentModule = _deployPaymentModule(createSalt);
        compensationModule = _deployCompensationModule(createSalt);
        _configureModuleKeeper(moduleKeeper, paymentModule, compensationModule);
    }

    /// @dev Deploys {ModuleKeeper} at a deterministic address across chains
    function _deployModuleKeeper(string memory createSalt) internal returns (ModuleKeeper moduleKeeper) {
        bytes32 salt = create3Salt("ModuleKeeper", createSalt);
        bytes memory args = abi.encode(DEFAULT_PROTOCOL_ADMIN);
        bytes memory moduleKeeperInitCode = abi.encodePacked(vm.getCode("ModuleKeeper.sol"), args);
        moduleKeeper = ModuleKeeper(CREATE3.deployDeterministic(moduleKeeperInitCode, salt));
    }

    /// @dev Deploys {StationRegistry} as an ERC1967 proxy at a deterministic address across chains
    /// and initializes it with a {Space} implementation
    /// Notes:
    /// - The proxy is deployed without initialization first to resolve the circular dependency with {Space}
    function _deployStationRegistry(
        string memory createSalt,
        ModuleKeeper moduleKeeper
    ) internal returns (StationRegistry stationRegistry) {
        // Deploy the {StationRegistry} implementation (non-deterministic)
        address implementation = address(new StationRegistry());

        // Deploy the proxy deterministically using CREATE3 without initialization
        // to resolve the circular dependency with {Space}
        bytes32 salt = create3Salt("StationRegistry", createSalt);
        bytes memory emptyData;
        bytes memory proxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, emptyData)
        );
        address proxy = CREATE3.deployDeterministic(proxyBytecode, salt);

        // Deploy the {Space} implementation deterministically with the proxy address as factory
        Space spaceImplementation = _deploySpaceImplementation(createSalt, proxy);

        // Initialize the {StationRegistry} proxy
        StationRegistry(proxy).initialize(
            DEFAULT_PROTOCOL_ADMIN,
            IEntryPoint(ENTRYPOINT_V6),
            moduleKeeper,
            address(spaceImplementation)
        );

        stationRegistry = StationRegistry(proxy);
    }

    /// @dev Deploys {Space} at a deterministic address across chains
    function _deploySpaceImplementation(
        string memory createSalt,
        address stationRegistryProxy
    ) internal returns (Space space) {
        bytes32 salt = create3Salt("Space", createSalt);
        bytes memory args = abi.encode(IEntryPoint(ENTRYPOINT_V6), stationRegistryProxy);
        bytes memory spaceInitCode = abi.encodePacked(vm.getCode("Space.sol"), args);
        space = Space(payable(CREATE3.deployDeterministic(spaceInitCode, salt)));
    }

    /// @dev Deploys {PaymentModule} as an ERC1967 proxy at a deterministic address across chains
    function _deployPaymentModule(string memory createSalt) internal returns (PaymentModule paymentModule) {
        bytes32 salt = create3Salt("PaymentModule", createSalt);
        address paymentModuleImplementation = address(new PaymentModule());
        bytes memory paymentModuleInitData = abi.encodeWithSelector(
            PaymentModule.initialize.selector,
            ISablierLockup(sablierLockupMap[block.chainid]),
            DEFAULT_PROTOCOL_ADMIN
        );
        bytes memory paymentModuleProxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(paymentModuleImplementation, paymentModuleInitData)
        );
        paymentModule = PaymentModule(CREATE3.deployDeterministic(paymentModuleProxyBytecode, salt));
    }

    /// @dev Deploys {CompensationModule} as an ERC1967 proxy at a deterministic address across chains
    function _deployCompensationModule(
        string memory createSalt
    ) internal returns (CompensationModule compensationModule) {
        bytes32 salt = create3Salt("CompensationModule", createSalt);
        address compensationModuleImplementation = address(new CompensationModule());
        bytes memory compensationModuleInitData = abi.encodeWithSelector(
            CompensationModule.initialize.selector,
            ISablierFlow(sablierFlowMap[block.chainid]),
            DEFAULT_PROTOCOL_ADMIN
        );
        bytes memory compensationModuleProxyBytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(compensationModuleImplementation, compensationModuleInitData)
        );

        compensationModule = CompensationModule(CREATE3.deployDeterministic(compensationModuleProxyBytecode, salt));
    }

    /// @dev Adds deployed modules and external contract addresses to the {ModuleKeeper} allowlist
    function _configureModuleKeeper(
        ModuleKeeper moduleKeeper,
        PaymentModule paymentModule,
        CompensationModule compensationModule
    ) internal {
        modules.push(address(paymentModule));
        modules.push(address(compensationModule));

        // Add the USDC, WETH and Across {SpokePool} deployments to the allowlist
        modules.push(address(usdcMap[block.chainid]));
        modules.push(address(wethMap[block.chainid]));
        modules.push(address(acrossSpokePoolMap[block.chainid]));

        // Add the {WerkSubdomainRegistrar} deployment to the allowlist if deployed on Base or Base Sepolia
        if (block.chainid == 8453 || block.chainid == 84_532) {
            modules.push(address(ensSubdomainRegistrarMap[block.chainid]));
        }

        moduleKeeper.addToAllowlist(modules);
    }
}
