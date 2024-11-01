// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title MockNonCompliantSpace
/// @notice A mock non-compliant {Space} contract that do not support the {ISpace} interface
contract MockNonCompliantSpace is IERC165 {
    address public owner;

    event ModuleExecutionSucceded(address module, uint256 value, bytes data);
    event ModuleExecutionFailed(address module, uint256 value, bytes data, bytes error);

    constructor(address _owner) {
        owner = _owner;
    }

    modifier onlyOwner() {
        _;
    }

    function execute(address module, uint256 value, bytes calldata data) public returns (bool success) {
        // Effects, Interactions: execute the call on the `module` contract
        success = _call(module, value, data);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }

    /// @dev Executes a low-level call on the `module` contract with the `data` data forwarding the `value` value
    function _call(address module, uint256 value, bytes calldata data) internal returns (bool success) {
        // Execute the call via assembly
        bytes memory result;
        (success, result) = module.call{ value: value }(data);

        // Revert with the same error returned by the module contract if the call failed
        if (!success) {
            assembly {
                revert(add(result, 0x20), mload(result))
            }
        } else {
            // Otherwise log the execution success
            emit ModuleExecutionSucceded(module, value, data);
        }
    }
}
