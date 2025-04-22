// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { ISablierFlow } from "@sablier/flow/src/interfaces/ISablierFlow.sol";

/// @title IFlowStreamManager
/// @notice Contract used to create and manage Sablier Flow compatible streams
/// @dev This code is referenced in the Sablier Flow docs: https://docs.sablier.com/guides/flow/overview
interface IFlowStreamManager {
    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice The address of the {SablierFlow} contract used to create compensation streams
    /// @dev This is initialized at construction time and it might be different depending on the deployment chain
    /// See https://docs.sablier.com/guides/flow/deployments
    function SABLIER_FLOW() external view returns (ISablierFlow);
}
