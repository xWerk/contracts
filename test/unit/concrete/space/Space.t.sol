// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import { Base_Test } from "../../../Base.t.sol";

contract Space_Unit_Concrete_Test is Base_Test {
    function setUp() public virtual override {
        Base_Test.setUp();

        address[] memory modules = new address[](1);
        modules[0] = address(mockModule);

        space = deploySpace({ _owner: users.eve, _spaceId: 0, _initialModules: modules });
    }
}
