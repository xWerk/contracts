// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "@thirdweb/contracts/prebuilts/account/interface/IAccountFactoryCore.sol";

/// @title IAccountFactory
/// @notice Fork of the thirdweb's `IAccountFactory` which removes the `salt` param from
/// `onSignerAdded` and `onSignerRemoved` methods
interface IAccountFactory is IAccountFactoryCore {
    /*///////////////////////////////////////////////////////////////
                        Callback Functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Callback function for an Account to register its signers.
    function onSignerAdded(address signer) external;

    /// @notice Callback function for an Account to un-register its signers.
    function onSignerRemoved(address signer) external;
}
