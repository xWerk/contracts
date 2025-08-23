// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Integration_Test } from "./Integration.t.sol";
import { Types } from "src/modules/compensation-module/libraries/Types.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Constants } from "test/utils/Constants.sol";

contract CompensationModule_Integration_Test is Integration_Test {
    function setUp() public virtual override {
        Integration_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    modifier whenCallerContract() {
        _;
    }

    modifier whenCallerComponentSender(address user) {
        vm.startPrank({ msgSender: user });

        _;
    }

    modifier whenCallerComponentRecipient(address user) {
        vm.startPrank({ msgSender: user });

        _;
    }

    modifier whenNonZeroAddressRecipient() {
        _;
    }

    modifier whenNonZeroAddressRecipients() {
        _;
    }

    modifier whenNonEmptyRecipientsArray() {
        _;
    }

    modifier whenNonZeroRatesPerSecond() {
        _;
    }

    modifier whenRecipientsAndComponentsArraysHaveSameLength() {
        _;
    }

    modifier whenNonZeroRatePerSecond() {
        _;
    }

    modifier whenComponentNotNull() {
        // Create a mock compensation component with 1 component
        Types.CompensationComponent memory component = createMockComponent(Types.ComponentType.Payroll);

        // Create the calldata for the `createComponent` function call with Bob as the recipient
        bytes memory data = abi.encodeWithSignature(
            "createComponent(address,uint128,uint8,address)",
            users.bob,
            component.ratePerSecond,
            uint8(component.componentType),
            address(component.asset)
        );

        // Create the compensation component
        space.execute({ module: address(compensationModule), value: 0, data: data });

        _;
    }

    modifier whenComponentPartiallyFunded() {
        // Create the calldata for the ERC-20 `approve` call to approve the compensation module to spend the ERC-20 tokens
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(compensationModule), 10e6);

        // Approve the compensation module to spend the ERC-20 tokens from Eve's Space
        space.execute({ module: address(usdt), value: 0, data: data });

        // Create the calldata for the `depositToComponent` call
        data = abi.encodeWithSignature("depositToComponent(uint256,uint128)", 1, 10e6);

        // Fund the compensation component with only 10 USDT which will be streamed in ~3 hours (at a rate of 86.4 USDT/day)
        space.execute({ module: address(compensationModule), value: 0, data: data });

        // Fast forward the time by 3 hours
        // After ~3 hours, the stream will be insolvent because all its balance will be fully streamed
        vm.warp(block.timestamp + 3 hours);

        _;
    }

    modifier whenComponentPaused() {
        // Create the calldata for the `pauseComponent` call
        bytes memory data = abi.encodeWithSignature("pauseComponent(uint256)", 1);

        // Pause the compensation component stream
        space.execute({ module: address(compensationModule), value: 0, data: data });

        _;
    }

    modifier whenComponentCancelled() {
        // Create the calldata for the `cancelComponent` call
        bytes memory data = abi.encodeWithSignature("cancelComponent(uint256)", 1);

        // Cancel the compensation component stream
        space.execute({ module: address(compensationModule), value: 0, data: data });

        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Creates a mock compensation component
    function createMockComponent(Types.ComponentType componentType)
        internal
        view
        returns (Types.CompensationComponent memory component)
    {
        component = Types.CompensationComponent({
            sender: address(space),
            recipient: users.bob,
            componentType: componentType,
            asset: IERC20(address(usdt)),
            ratePerSecond: Constants.RATE_PER_SECOND,
            streamId: 0
        });
    }
}
