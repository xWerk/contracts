// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

contract MockAdmin {
    enum Protocol {
        Airdrops,
        Flow,
        Lockup,
        Staking
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }

    function calculateMinFeeWei(Protocol) external pure returns (uint256) {
        return 1e5;
    }

    function calculateMinFeeWeiFor(Protocol, address) external pure returns (uint256) {
        return 1e5;
    }
}
