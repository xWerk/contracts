// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Integration_Test } from "./Integration.t.sol";
import { SubscriptionModule } from "src/modules/subscription-module/SubscriptionModule.sol";
import { Types } from "src/modules/subscription-module/libraries/Types.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

abstract contract SubscriptionModule_Integration_Test is Integration_Test {
    /*//////////////////////////////////////////////////////////////////////////
                                   TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    SubscriptionModule internal subscriptionModule;

    /// @dev The treasury address that receives all subscription charges
    address internal treasury;

    /*//////////////////////////////////////////////////////////////////////////
                                   TEST STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Default subscription terms reused across the test suite
    uint8 internal constant TIER = 1;
    uint128 internal constant AMOUNT = 100e6; // 100 USDT per cycle
    uint40 internal constant INTERVAL = 30 days;
    uint16 internal constant PERIODS = 12;

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual override {
        Integration_Test.setUp();

        // Use a dedicated treasury address
        treasury = makeAddr("treasury");

        // Deploy the {SubscriptionModule} behind a proxy, owned by the admin, with USDT as the initial asset
        address implementation = address(new SubscriptionModule());
        bytes memory data =
            abi.encodeWithSelector(SubscriptionModule.initialize.selector, users.admin, treasury, address(usdt));
        subscriptionModule = SubscriptionModule(address(new ERC1967Proxy(implementation, data)));

        // Configure the default tier as the admin (owner)
        vm.prank(users.admin);
        subscriptionModule.setTier(TIER, AMOUNT, INTERVAL);

        // Allowlist the {SubscriptionModule} so the {Space} can call it through `execute`
        address[] memory subModules = new address[](1);
        subModules[0] = address(subscriptionModule);
        allowlistModules(subModules);

        vm.label({ account: address(subscriptionModule), newLabel: "SubscriptionModule" });
        vm.label({ account: treasury, newLabel: "Treasury" });
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Subscribes the {Space} to the default tier through its smart account, starting now
    function subscribeThroughSpace() internal {
        subscribeThroughSpace(TIER, address(usdt), PERIODS, uint40(block.timestamp));
    }

    /// @dev Subscribes by calling `subscribe` through the `space` smart account
    function subscribeThroughSpace(uint8 tier, address asset, uint16 periods, uint40 start) internal {
        bytes memory data = abi.encodeWithSelector(SubscriptionModule.subscribe.selector, tier, asset, periods, start);
        space.execute({ module: address(subscriptionModule), value: 0, data: data });
    }

    /// @dev Cancels the `space` subscription by calling `cancel` through the `space` smart account
    function cancelThroughSpace() internal {
        bytes memory data = abi.encodeWithSelector(SubscriptionModule.cancel.selector);
        space.execute({ module: address(subscriptionModule), value: 0, data: data });
    }

    /// @dev Approves the {SubscriptionModule} to spend `amount` of USDT from the `space`
    function approveModuleThroughSpace(uint256 amount) internal {
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", address(subscriptionModule), amount);
        space.execute({ module: address(usdt), value: 0, data: data });
    }
}
