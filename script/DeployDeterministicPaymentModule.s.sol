// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { PaymentModule } from "src/modules/payment-module/PaymentModule.sol";
import { CREATE3 } from "solady/src/utils/CREATE3.sol";
import { ISablierLockup } from "@sablier/lockup/src/interfaces/ISablierLockup.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Deterministically deploys an instance of {PaymentModule}
/// @dev Uses `CREATE3` for deterministic proxy deployment across all EVM chains
contract DeployPaymentModule is BaseScript {
    function run() public virtual broadcast returns (PaymentModule paymentModule) {
        // Create deterministic salt
        bytes32 salt = createSalt("PaymentModule");

        // Deploy the {PaymentModule} implementation (non-deterministic)
        address paymentModuleImplementation = address(new PaymentModule());

        // Encode initialization data for the proxy constructor
        bytes memory initData = abi.encodeWithSelector(
            PaymentModule.initialize.selector,
            ISablierLockup(sablierLockupMap[block.chainid]),
            DEFAULT_PROTOCOL_OWNER,
            DEFAULT_BROKER_ADMIN,
            DEFAULT_BROKER_FEE
        );

        // Construct the ERC1967Proxy bytecode with implementation and initData
        bytes memory proxyBytecode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(paymentModuleImplementation, initData));

        // Deploy the proxy deterministically using CREATE3
        paymentModule = PaymentModule(CREATE3.deployDeterministic(proxyBytecode, salt));
    }
}
