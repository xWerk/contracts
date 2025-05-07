// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { CompensationModule } from "./../src/modules/compensation-module/CompensationModule.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Options } from "@openzeppelin/foundry-upgrades/src/Options.sol";
import { Core } from "@openzeppelin/foundry-upgrades/src/internal/Core.sol";
import { ISablierFlow } from "@sablier/flow/src/interfaces/ISablierFlow.sol";
import { ud } from "@prb/math/src/UD60x18.sol";

/// @notice Deploys at deterministic addresses across chains an instance of {CompensationModule}
/// @dev Reverts if any contract has already been deployed
contract DeployDeterministicCompensationModule is BaseScript {
    /// @dev By using a salt, Forge will deploy the contract via a deterministic CREATE2 factory
    /// https://book.getfoundry.sh/tutorials/create2-tutorial?highlight=deter#deterministic-deployment-using-create2
    function run(
        string memory create2Salt,
        ISablierFlow sablierFlow,
        address initialOwner,
        address brokerAccount
    )
        public
        virtual
        broadcast
        returns (CompensationModule compensationModule)
    {
        bytes32 salt = bytes32(abi.encodePacked(create2Salt));

        // Deterministically deploy the {CompensationModule} module
        compensationModule = CompensationModule(
            deployDetermisticUUPSProxy(
                salt,
                "",
                "CompensationModule.sol",
                abi.encodeCall(CompensationModule.initialize, (sablierFlow, initialOwner, brokerAccount, ud(0)))
            )
        );
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
