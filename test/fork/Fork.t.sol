// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Base_Test } from "../Base.t.sol";
import { Users } from "../utils/Types.sol";

abstract contract Fork_Test is Base_Test {
    function setUp() public virtual override {
        // Create test users
        users = Users({ admin: createUser("admin"), eve: createUser("eve"), bob: createUser("bob") });
    }

    /// @dev Generates a user, labels its address, and funds it with test assets
    function createUser(string memory name) internal override returns (address payable) {
        address payable user = payable(makeAddr(name));
        vm.deal({ account: user, newBalance: 100 ether });

        return user;
    }
}
