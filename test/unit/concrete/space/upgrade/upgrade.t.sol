// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Space_Unit_Concrete_Test } from "../Space.t.sol";
import { SpaceV2 } from "test/mocks/MockSpaceV2.sol";
import { Errors } from "src/libraries/Errors.sol";
import { IEntryPoint } from "@thirdweb/contracts/prebuilts/account/interface/IEntrypoint.sol";

contract Upgrade_Unit_Concrete_Test is Space_Unit_Concrete_Test {
    SpaceV2 internal spaceV2Implementation;

    function setUp() public virtual override {
        Space_Unit_Concrete_Test.setUp();

        // Deploy SpaceV2 implementation for upgrade tests
        spaceV2Implementation = new SpaceV2(IEntryPoint(entrypoint), address(stationRegistry));
    }

    function test_Version() external view {
        // Verify the VERSION returns "1.0.0" for the initial deployment
        assertEq(space.VERSION(), "1.0.0");
    }

    function test_RevertWhen_UpgradeCalledByNonAdmin() external {
        // Make Bob the caller who is not the admin of the space
        vm.startPrank({ msgSender: users.bob });

        // Expect the next call to revert with the {CallerNotEntryPointOrAdmin} error
        vm.expectRevert(Errors.CallerNotEntryPointOrAdmin.selector);

        // Attempt to upgrade
        space.upgradeToAndCall(address(spaceV2Implementation), "");
    }

    modifier whenCallerAdmin() {
        // Make Eve the caller as she's the admin of the space
        vm.startPrank({ msgSender: users.eve });
        _;
    }

    function test_UpgradeToAndCall_AsAdmin() external whenCallerAdmin {
        // Upgrade the space to V2
        space.upgradeToAndCall(address(spaceV2Implementation), "");

        // Verify VERSION is now "2.0.0"
        assertEq(space.VERSION(), "2.0.0");

        // Verify new feature is accessible
        assertEq(SpaceV2(payable(address(space))).newFeature(), "V2");
    }

    function test_UpgradeToAndCall_ViaEntryPoint() external {
        // Simulate call from EntryPoint
        vm.startPrank({ msgSender: entrypoint });

        // Upgrade the space to V2
        space.upgradeToAndCall(address(spaceV2Implementation), "");

        // Verify VERSION is now "2.0.0"
        assertEq(space.VERSION(), "2.0.0");
    }

    function test_StatePreservedAfterUpgrade() external whenCallerAdmin {
        // Record state before upgrade
        address adminBefore = users.eve;
        uint256 balanceBefore = address(space).balance;
        uint256 usdtBalanceBefore = usdt.balanceOf(address(space));

        // Verify admin status before upgrade
        assertTrue(space.isAdmin(adminBefore));

        // Upgrade the space to V2
        space.upgradeToAndCall(address(spaceV2Implementation), "");

        // Verify state is preserved after upgrade
        assertTrue(space.isAdmin(adminBefore));
        assertEq(address(space).balance, balanceBefore);
        assertEq(usdt.balanceOf(address(space)), usdtBalanceBefore);

        // Verify VERSION changed to V2
        assertEq(space.VERSION(), "2.0.0");
    }
}
