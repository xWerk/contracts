// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { CompensationModule_Integration_Test } from "test/integration/CompensationModule.t.sol";
import { Errors } from "src/modules/compensation-module/libraries/Errors.sol";
import { Types } from "src/modules/compensation-module/libraries/Types.sol";
import { Flow } from "@sablier/flow/src/types/DataTypes.sol";
import { ICompensationModule } from "src/modules/compensation-module/interfaces/ICompensationModule.sol";
import { ud, UD60x18 } from "@prb/math/src/UD60x18.sol";

contract DepositToComponent_Integration_Concrete_Test is CompensationModule_Integration_Test {
    uint128 constant DEPOSIT_AMOUNT = 10e6;

    function setUp() public override {
        CompensationModule_Integration_Test.setUp();

        // Make Eve the caller by default in all test suites as she's the owner of the {Space} contract
        vm.startPrank({ msgSender: users.eve });
    }

    function test_RevertWhen_ComponentNull() public {
        // Expect the call to revert with the {ComponentNull} error
        vm.expectRevert(Errors.ComponentNull.selector);

        // Run the test
        compensationModule.depositToComponent({ componentId: 1, amount: DEPOSIT_AMOUNT });
    }

    function test_RevertWhen_InvalidZeroDepositAmount() public whenComponentNotNull {
        // Expect the call to revert with the {InvalidZeroDepositAmount} error
        vm.expectRevert(Errors.InvalidZeroDepositAmount.selector);

        // Run the test
        compensationModule.depositToComponent({ componentId: 1, amount: 0 });
    }

    function test_GivenNonZeroBrokerFee_DepositToComponent() public whenComponentNotNull {
        // Change the prank to the admin to update the broker fee
        vm.startPrank({ msgSender: users.admin });

        // Update the broker fee
        UD60x18 BROKER_FEE = ud(0.005e18);
        compensationModule.updateStreamBrokerFee(BROKER_FEE);

        // Calculate the fee amount based on the fee percentage.
        uint128 feeAmount = ud(DEPOSIT_AMOUNT).mul(BROKER_FEE).intoUint128();

        // Switch the prank back to Eve
        vm.startPrank({ msgSender: users.eve });

        // Create the calldata for the ERC-20 `approve` call to approve the compensation module to spend the ERC-20 tokens
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(compensationModule), 10e6);

        // Approve the compensation module to spend the ERC-20 tokens from Eve's Space
        space.execute({ module: address(usdt), value: 0, data: data });

        // Create the calldata for the `depositToComponent` call
        data = abi.encodeWithSelector(compensationModule.depositToComponent.selector, 1, DEPOSIT_AMOUNT);

        // Expect the {ComponentDeposited} event to be emitted
        vm.expectEmit();
        emit ICompensationModule.ComponentDeposited({ componentId: 1, amount: DEPOSIT_AMOUNT });

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Retrieve the compensation component
        Types.CompensationComponent memory component = compensationModule.getComponent({ componentId: 1 });

        // Retrieve the component stream
        Flow.Stream memory stream = compensationModule.getComponentStream(component.streamId);

        // Assert the actual and expected stream balance
        assertEq(stream.balance, DEPOSIT_AMOUNT - feeAmount);
    }

    function test_DepositToComponent() public whenComponentNotNull {
        // Create the calldata for the ERC-20 `approve` call to approve the compensation module to spend the ERC-20 tokens
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(compensationModule), 10e6);

        // Approve the compensation module to spend the ERC-20 tokens from Eve's Space
        space.execute({ module: address(usdt), value: 0, data: data });

        // Create the calldata for the `depositToComponent` call
        data = abi.encodeWithSelector(compensationModule.depositToComponent.selector, 1, DEPOSIT_AMOUNT);

        // Expect the {ComponentDeposited} event to be emitted
        vm.expectEmit();
        emit ICompensationModule.ComponentDeposited({ componentId: 1, amount: DEPOSIT_AMOUNT });

        // Run the test
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Retrieve the compensation component
        Types.CompensationComponent memory component = compensationModule.getComponent({ componentId: 1 });

        // Retrieve the component stream
        Flow.Stream memory stream = compensationModule.getComponentStream(component.streamId);

        // Assert the actual and expected stream balance
        assertEq(stream.balance, DEPOSIT_AMOUNT);
    }
}
