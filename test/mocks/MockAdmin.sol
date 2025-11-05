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

    function calculateMinFeeWei(Protocol protocol) external pure returns (uint256) {
        return 0;
    }

    function calculateMinFeeWeiFor(Protocol protocol, address user) external pure returns (uint256) {
        return 0;
    }
}
