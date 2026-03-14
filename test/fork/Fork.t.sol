// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Base_Test } from "../Base.t.sol";
import { Users } from "../utils/Types.sol";
import { MockERC20NoReturn } from "../mocks/MockERC20NoReturn.sol";
import { ModuleKeeper } from "src/ModuleKeeper.sol";
import { IEntryPoint } from "@thirdweb/contracts/prebuilts/account/interface/IEntrypoint.sol";

abstract contract Fork_Test is Base_Test {
    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual override {
        // Create test users
        users = Users({
            admin: createUser("admin"), eve: createUser("eve"), bob: createUser("bob"), alice: createUser("alice")
        });

        // Deploy mock USDT (needed by Base_Test.deploySpace for funding)
        usdt = new MockERC20NoReturn("Tether USD", "USDT", 6);

        // Deploy Werk infrastructure: ModuleKeeper → StationRegistry → Spaces
        moduleKeeper = new ModuleKeeper({ _initialOwner: users.admin });
        stationRegistry = _deployStationRegistry(users.admin, IEntryPoint(address(0)), moduleKeeper);

        // Deploy two Space instances
        space = deploySpace(users.alice);
        vm.label(address(space), "werkSpace");
        space2 = deploySpace(users.bob);
        vm.label(address(space2), "werkSpace2");
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    OTHER HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Generates a user, labels its address, and funds it with test assets
    function createUser(string memory name) internal override returns (address payable) {
        address payable user = payable(makeAddr(name));
        vm.deal({ account: user, newBalance: 100 ether });

        return user;
    }
}
