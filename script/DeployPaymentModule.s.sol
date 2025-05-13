// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "./Base.s.sol";
import { PaymentModule } from "src/modules/payment-module/PaymentModule.sol";
import { ISablierLockup } from "@sablier/lockup/src/interfaces/ISablierLockup.sol";
import { Upgrades } from "@openzeppelin/foundry-upgrades/src/Upgrades.sol";

/// @notice Deploys an instance of {PaymentModule}
contract DeployPaymentModule is BaseScript {
    function run() public virtual broadcast returns (PaymentModule paymentModule) {
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
    }
}
