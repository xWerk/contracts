// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { PaymentModule } from "src/modules/payment-module/PaymentModule.sol";
import { CompensationModule } from "src/modules/compensation-module/CompensationModule.sol";
import { StationRegistry } from "src/StationRegistry.sol";
import { ModuleKeeper } from "src/ModuleKeeper.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Options } from "@openzeppelin/foundry-upgrades/src/Options.sol";
import { Core } from "@openzeppelin/foundry-upgrades/src/internal/Core.sol";
import { ISablierLockup } from "@sablier/lockup/src/interfaces/ISablierLockup.sol";
import { ISablierFlow } from "@sablier/flow/src/interfaces/ISablierFlow.sol";
import { IEntryPoint } from "@thirdweb/contracts/prebuilts/account/interface/IEntrypoint.sol";
import { ud } from "@prb/math/src/UD60x18.sol";

/// @notice Deploys at deterministic addresses across chains the core contracts of the Werk Protocol
/// @dev Reverts if any contract has already been deployed
contract DeployDeterministicCore is BaseScript {
    address[] modules;

    /// @dev By using a salt, Forge will deploy the contract via a deterministic CREATE2 factory
    /// https://book.getfoundry.sh/tutorials/create2-tutorial?highlight=deter#deterministic-deployment-using-create2
    function run(
        string memory create2Salt,
        ISablierLockup sablierLockup,
        ISablierFlow sablierFlow,
        address initialOwner,
        address brokerAccount,
        IEntryPoint entrypoint
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
        bytes32 salt = bytes32(abi.encodePacked(create2Salt));

        // Deterministically deploy the {ModuleKeeper} contract
        moduleKeeper = new ModuleKeeper{ salt: salt }(initialOwner);

        // Deterministically deploy the {StationRegistry} contract
        stationRegistry = new StationRegistry{ salt: salt }(initialOwner, entrypoint, moduleKeeper);

        // Deterministically deploy the {PaymentModule} module
        paymentModule = PaymentModule(
            deployDetermisticUUPSProxy(
                salt,
                "",
                "PaymentModule.sol",
                abi.encodeCall(PaymentModule.initialize, (sablierLockup, initialOwner, brokerAccount, ud(0)))
            )
        );

        // Deterministically deploy the {CompensationModule} module
        compensationModule = CompensationModule(
            deployDetermisticUUPSProxy(
                salt,
                "",
                "CompensationModule.sol",
                abi.encodeCall(CompensationModule.initialize, (sablierFlow, initialOwner, brokerAccount, ud(0)))
            )
        );

        // Add the {PaymentModule} and {CompensationModule} modules to the allowlist of the {ModuleKeeper}
        modules.push(address(paymentModule));
        modules.push(address(compensationModule));
        moduleKeeper.addToAllowlist(modules);
    }

    /// @dev Deploys a UUPS proxy at deterministic addresses across chains based on a provided salt
    /// @param salt Salt to use for deterministic deployment
    /// @param contractName The name of the implementation contract
    /// @param initializerData The ABI encoded call to be made to the initialize method
    function deployDetermisticUUPSProxy(
        bytes32 salt,
        bytes memory constructorData,
        string memory contractName,
        bytes memory initializerData
    )
        internal
        returns (address)
    {
        Options memory opts;
        opts.constructorData = constructorData;

        address impl = Core.deployImplementation(contractName, opts);

        return address(new ERC1967Proxy{ salt: salt }(impl, initializerData));
    }
}
