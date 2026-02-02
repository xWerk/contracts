// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Base_Test } from "../../../../Base.t.sol";
import { StationRegistryV2 } from "test/mocks/MockStationRegistryV2.sol";
import { Constants } from "../../../../utils/Constants.sol";

contract Upgrade_StationRegistry_Unit_Concrete_Test is Base_Test {
    StationRegistryV2 internal stationRegistryV2Implementation;

    function setUp() public virtual override {
        Base_Test.setUp();

        // Deploy StationRegistryV2 implementation for upgrade tests
        stationRegistryV2Implementation = new StationRegistryV2();
    }

    function test_Version() external view {
        // Verify the VERSION returns "1.0.0" for the initial deployment
        assertEq(stationRegistry.VERSION(), "1.0.0");
    }

    function test_RevertWhen_UpgradeCalledByNonAdmin() external {
        // Make Bob the caller who does not have DEFAULT_ADMIN_ROLE
        vm.startPrank({ msgSender: users.bob });

        // Expect the next call to revert (AccessControl error)
        vm.expectRevert();

        // Attempt to upgrade
        stationRegistry.upgradeToAndCall(address(stationRegistryV2Implementation), "");
    }

    modifier whenCallerHasAdminRole() {
        // Make admin the caller as they have DEFAULT_ADMIN_ROLE
        vm.startPrank({ msgSender: users.admin });
        _;
    }

    function test_UpgradeToAndCall_AsAdmin() external whenCallerHasAdminRole {
        // Upgrade the station registry to V2
        stationRegistry.upgradeToAndCall(address(stationRegistryV2Implementation), "");

        // Verify VERSION is now "2.0.0"
        assertEq(stationRegistry.VERSION(), "2.0.0");

        // Verify new feature is accessible
        assertEq(StationRegistryV2(address(stationRegistry)).newFeature(), "V2");
    }

    function test_StatePreservedAfterUpgrade() external whenCallerHasAdminRole {
        // Stop the admin prank to deploy a Space
        vm.stopPrank();

        // Deploy a Space first to have some state
        space = deploySpace({ _owner: users.eve, _stationId: 0 });

        // Restart the admin prank for upgrade
        vm.startPrank({ msgSender: users.admin });

        // Record state before upgrade
        address moduleKeeperBefore = address(stationRegistry.moduleKeeper());
        address spaceImplBefore = stationRegistry.accountImplementation();
        uint256 stationIdOfSpaceBefore = stationRegistry.stationIdOfSpace(address(space));
        address ownerOfStationBefore = stationRegistry.ownerOfStation(1);

        // Verify admin role before upgrade
        assertTrue(stationRegistry.hasRole(Constants.DEFAULT_ADMIN_ROLE, users.admin));

        // Upgrade the station registry to V2
        stationRegistry.upgradeToAndCall(address(stationRegistryV2Implementation), "");

        // Verify state is preserved after upgrade
        assertEq(address(stationRegistry.moduleKeeper()), moduleKeeperBefore);
        assertEq(stationRegistry.accountImplementation(), spaceImplBefore);
        assertEq(stationRegistry.stationIdOfSpace(address(space)), stationIdOfSpaceBefore);
        assertEq(stationRegistry.ownerOfStation(1), ownerOfStationBefore);

        // Verify admin role is preserved
        assertTrue(stationRegistry.hasRole(Constants.DEFAULT_ADMIN_ROLE, users.admin));

        // Verify VERSION changed to V2
        assertEq(stationRegistry.VERSION(), "2.0.0");
    }

    function test_CanStillCreateSpaceAfterUpgrade() external whenCallerHasAdminRole {
        // Upgrade the station registry to V2
        stationRegistry.upgradeToAndCall(address(stationRegistryV2Implementation), "");

        vm.stopPrank();

        // Deploy a Space after upgrade
        space = deploySpace({ _owner: users.eve, _stationId: 0 });

        // Verify Space was created successfully
        assertTrue(address(space) != address(0));
        assertEq(stationRegistry.stationIdOfSpace(address(space)), 1);
        assertEq(stationRegistry.ownerOfStation(1), users.eve);
    }
}
