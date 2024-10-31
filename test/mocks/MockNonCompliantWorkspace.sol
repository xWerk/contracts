// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { ExcessivelySafeCall } from "@nomad-xyz/excessively-safe-call/src/ExcessivelySafeCall.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title Space
/// @notice A mock non-compliant space contract that do not support the {ISpace} interface
contract MockNonCompliantWorkspace is IERC165 {
    using ExcessivelySafeCall for address;

    address public owner;

    event ModuleExecutionSucceded(address module, uint256 value, bytes data);
    event ModuleExecutionFailed(address module, uint256 value, bytes data, bytes error);

    constructor(address _owner) {
        owner = _owner;
    }

    modifier onlyOwner() {
        _;
    }

    function execute(address module, uint256 value, bytes memory data) external onlyOwner returns (bool success) {
        // Allocate all the gas to the executed module method
        uint256 txGas = gasleft();

        // Execute the call via assembly and get only the first 4 bytes of the returndata
        // which will be the selector of the error in case of a revert in the module contract
        // See https://github.com/nomad-xyz/ExcessivelySafeCall
        bytes memory result;
        (success, result) = module.excessivelySafeCall({ _gas: txGas, _value: 0, _maxCopy: 4, _calldata: data });

        if (!success) {
            // Revert with the same error returned by the module contract
            assembly {
                revert(add(result, 0x20), 4)
            }
            // Log the execution success
        } else {
            emit ModuleExecutionSucceded(module, value, data);
        }
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}
