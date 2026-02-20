// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { PaymentModule } from "src/modules/payment-module/PaymentModule.sol";
import { CREATE3 } from "solady/src/utils/CREATE3.sol";
import { ISablierLockup } from "@sablier/lockup/src/interfaces/ISablierLockup.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Deterministically deploys an instance of {PaymentModule}
/// @dev Reverts if any contract has already been deployed
contract DeployDeterministicPaymentModule is BaseScript {
    function run(string memory inputSalt) public virtual broadcast returns (PaymentModule paymentModule) {
        // Construct the CREATE3 salt based on the contract name and the provided input salt
        bytes32 salt = constructCreate3Salt("PaymentModule", inputSalt);

        // Deploy the {PaymentModule} implementation (non-deterministic)
        address paymentModuleImplementation = address(new PaymentModule());

        // Encode initialization data for the proxy constructor
        bytes memory initData = abi.encodeWithSelector(
            PaymentModule.initialize.selector, ISablierLockup(sablierLockupMap[block.chainid]), DEFAULT_PROTOCOL_ADMIN
        );

        // Construct the ERC1967Proxy bytecode with implementation and initData
        bytes memory proxyBytecode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(paymentModuleImplementation, initData));

        // Deploy the proxy deterministically using CREATE3
        paymentModule = PaymentModule(CREATE3.deployDeterministic(proxyBytecode, salt));
    }
}
