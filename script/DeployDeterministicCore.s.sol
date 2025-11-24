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

/// @notice Deploys the Werk Protocol core contracts deterministically across all supported EVM chains
/// @dev Reverts if any contract has already been deployed
contract DeployDeterministicCore is BaseScript {
    address[] modules;

    /// @dev Uses `CREATE2` and `CREATE3` to ensure the same deployment addresses across chains
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
        // Deploy {ModuleKeeper} at a deterministic address across chains
        bytes32 salt = create3Salt("ModuleKeeper", createSalt);
        bytes memory args = abi.encode(DEFAULT_PROTOCOL_ADMIN);
        bytes memory moduleKeeperInitCode = abi.encodePacked(vm.getCode("ModuleKeeper.sol"), args);
        moduleKeeper = ModuleKeeper(CREATE3.deployDeterministic(moduleKeeperInitCode, salt));

        // Deploy {StationRegistry} at a deterministic address across chains
        salt = create3Salt("StationRegistry", createSalt);
        args = abi.encode(DEFAULT_PROTOCOL_ADMIN, IEntryPoint(ENTRYPOINT_V6), moduleKeeper);
        bytes memory stationRegistryInitCode = abi.encodePacked(vm.getCode("StationRegistry.sol"), args);
        stationRegistry = StationRegistry(CREATE3.deployDeterministic(stationRegistryInitCode, salt));

        // Deploy {PaymentModule} at a deterministic address across chains
        salt = create3Salt("PaymentModule", createSalt);
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

        // Deploy {CompensationModule} at a deterministic address across chains
        salt = create3Salt("CompensationModule", createSalt);
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

        // Add the {PaymentModule} and {CompensationModule} modules to the allowlist of the {ModuleKeeper}
        modules.push(address(paymentModule));
        modules.push(address(compensationModule));

        // Add the USDC, WETH and Across {SpokePool} deployments to the allowlist of the {ModuleKeeper}
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
