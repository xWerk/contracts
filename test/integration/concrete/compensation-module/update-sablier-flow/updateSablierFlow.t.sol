// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Types } from "src/modules/payment-module/libraries/Types.sol";
import { IFlowStreamManager } from "src/modules/compensation-module/sablier-flow/interfaces/IFlowStreamManager.sol";
import { Integration_Test } from "test/integration/Integration.t.sol";
import { ISablierFlow } from "@sablier/flow/src/interfaces/ISablierFlow.sol";

contract UpdateSablierFlow_Integration_Concret_Test is Integration_Test {
    Types.PaymentRequest paymentRequest;

    function setUp() public virtual override {
        Integration_Test.setUp();
    }

    function test_RevertWhen_CallerNotOwner() external {
        // Make Bob the caller in this test suite who is not the owner
        vm.startPrank({ msgSender: users.bob });

        // Expect the call to revert with the {OwnableUnauthorizedAccount} error
        vm.expectRevert(
            abi.encodeWithSelector(bytes4(keccak256(bytes("OwnableUnauthorizedAccount(address)"))), users.bob)
        );

        // Run the test
        compensationModule.updateSablierFlow(ISablierFlow(address(0x123)));
    }

    modifier whenCallerOwner() {
        // Make Admin the caller in this test suite
        vm.startPrank({ msgSender: users.admin });

        _;
    }

    function test_UpdateSablierFlow() external whenCallerOwner {
        ISablierFlow newSablierFlow = ISablierFlow(address(0x123));

        // Expect the {SablierFlowAddressUpdated} to be emitted
        vm.expectEmit();
        emit IFlowStreamManager.SablierFlowAddressUpdated({
            oldAddress: ISablierFlow(address(sablierFlow)),
            newAddress: ISablierFlow(address(0x123))
        });

        // Run the test
        compensationModule.updateSablierFlow(newSablierFlow);

        // Assert the actual and expected broker fee
        ISablierFlow actualSablierFlow = compensationModule.SABLIER_FLOW();
        assertEq(address(actualSablierFlow), address(newSablierFlow));
    }
}
