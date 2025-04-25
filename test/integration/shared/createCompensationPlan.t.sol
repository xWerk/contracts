// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Integration_Test } from "../Integration.t.sol";
import { Types } from "./../../../../../src/modules/compensation-module/libraries/Types.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Constants } from "./../../utils/Constants.sol";

abstract contract CreateCompensationPlan_Integration_Shared_Test is Integration_Test {
    function setUp() public virtual override {
        Integration_Test.setUp();
    }

    modifier whenCallerContract() {
        _;
    }

    modifier whenCompliantSpace() {
        _;
    }

    modifier whenNonZeroAddressRecipient() {
        _;
    }

    modifier whenNonZeroComponentsArray() {
        _;
    }

    modifier whenNonZeroRatePerSecond() {
        _;
    }

    /// @dev Creates a mock compensation plan with a pre-defined rate per second
    function createMockCompensationPlan(Types.ComponentType componentType)
        internal
        view
        returns (Types.Component[] memory components)
    {
        components = new Types.Component[](1);
        components[0] = Types.Component({
            componentType: componentType,
            asset: IERC20(address(usdt)),
            ratePerSecond: Constants.RATE_PER_SECOND,
            streamId: 0
        });

        return components;
    }
}
