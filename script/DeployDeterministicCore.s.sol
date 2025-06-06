// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { PaymentModule } from "src/modules/payment-module/PaymentModule.sol";
import { CompensationModule } from "src/modules/compensation-module/CompensationModule.sol";
import { StationRegistry } from "src/StationRegistry.sol";
import { ModuleKeeper } from "src/ModuleKeeper.sol";
import { Upgrades } from "@openzeppelin/foundry-upgrades/src/Upgrades.sol";
import { Core } from "@openzeppelin/foundry-upgrades/src/internal/Core.sol";
import { ISablierLockup } from "@sablier/lockup/src/interfaces/ISablierLockup.sol";
import { ISablierFlow } from "@sablier/flow/src/interfaces/ISablierFlow.sol";
import { IEntryPoint } from "@thirdweb/contracts/prebuilts/account/interface/IEntrypoint.sol";

/// @notice Deploys at deterministic addresses across chains the core contracts of the Werk Protocol
/// @dev Reverts if any contract has already been deployed
contract DeployDeterministicCore is BaseScript {
    address[] modules;

    /// @dev By using a salt, Forge will deploy the contract via a deterministic CREATE2 factory
    /// https://book.getfoundry.sh/tutorials/create2-tutorial?highlight=deter#deterministic-deployment-using-create2
    function run(string memory create2Salt)
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
        bytes32 salt = bytes32(abi.encodePacked(create2Salt));

        // Deterministically deploy the {ModuleKeeper} contract
        moduleKeeper = new ModuleKeeper{ salt: salt }(DEFAULT_PROTOCOL_OWNER);

        // Deterministically deploy the {StationRegistry} contract
        stationRegistry =
            new StationRegistry{ salt: salt }(DEFAULT_PROTOCOL_OWNER, IEntryPoint(ENTRYPOINT_V6), moduleKeeper);

        // Deploy the {PaymentModule} module
        // The proxy cannot be deterministically deployed because the `initializerData` which is passed in the constructor, differ between chains
        paymentModule = PaymentModule(
            Upgrades.deployUUPSProxy(
                "PaymentModule.sol",
                abi.encodeCall(
                    PaymentModule.initialize,
                    (
                        ISablierLockup(sablierLockupMap[block.chainid]),
                        DEFAULT_PROTOCOL_OWNER,
                        DEFAULT_BROKER_ADMIN,
                        DEFAULT_BROKER_FEE
                    )
                )
            )
        );

        // Deploy the {CompensationModule} module
        // The proxy cannot be deterministically deployed because the `initializerData` which is passed in the constructor, differ between chains
        compensationModule = CompensationModule(
            Upgrades.deployUUPSProxy(
                "CompensationModule.sol",
                abi.encodeCall(
                    CompensationModule.initialize,
                    (
                        ISablierFlow(sablierFlowMap[block.chainid]),
                        DEFAULT_PROTOCOL_OWNER,
                        DEFAULT_BROKER_ADMIN,
                        DEFAULT_BROKER_FEE
                    )
                )
            )
        );

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
