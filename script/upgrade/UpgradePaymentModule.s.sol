// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { BaseScript } from "../Base.s.sol";
import { PaymentModule } from "../../src/modules/payment-module/PaymentModule.sol";
import { Upgrades } from "@openzeppelin/foundry-upgrades/src/Upgrades.sol";
import { Options } from "@openzeppelin/foundry-upgrades/src/Options.sol";
import { ISablierV2LockupLinear } from "@sablier/v2-core/src/interfaces/ISablierV2LockupLinear.sol";
import { ISablierV2LockupTranched } from "@sablier/v2-core/src/interfaces/ISablierV2LockupTranched.sol";

/// @notice Upgrades the {PaymentModule} module based on a previous build
contract UpgradePaymentModule is BaseScript {
    function run(
        address paymentModule,
        ISablierV2LockupLinear sablierLockupLinear,
        ISablierV2LockupTranched sablierLockupTranched
    )
        public
        virtual
        broadcast
    {
        Options memory opts;
        opts.referenceBuildInfoDir = "./old-out/build-info-v1/";
        opts.referenceContract = "build-info-v1:PaymentModule";
        opts.constructorData = abi.encode(sablierLockupLinear, sablierLockupTranched);

        Upgrades.upgradeProxy(paymentModule, "PaymentModule.sol", "", opts);
    }
}
