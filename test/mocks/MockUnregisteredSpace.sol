// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { ISpace } from "src/interfaces/ISpace.sol";

/// @title MockUnregisteredSpace
/// @notice A mock {Space} contract that claims to support the {ISpace} interface without being deployed
/// nor registered by the {StationRegistry}
contract MockUnregisteredSpace is IERC165 {
    function execute(address module, uint256 value, bytes calldata data) public returns (bool success) {
        // Effects, Interactions: execute the call on the `module` contract
        bytes memory result;
        (success, result) = module.call{ value: value }(data);

        // Revert with the same error returned by the module contract if the call failed
        if (!success) {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        }
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(ISpace).interfaceId;
    }
}
