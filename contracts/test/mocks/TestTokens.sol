// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockUSDC} from "./MockUSDC.sol";

interface ITokenHook {
    function onTokenReceived() external;
}

/// @notice MockUSDC that calls back into `hookTarget` after a transfer to it (ERC-777 style hook).
contract HookUSDC is MockUSDC {
    address public hookTarget;

    function setHookTarget(address target) external {
        hookTarget = target;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (from != address(0) && to != address(0) && to == hookTarget) {
            ITokenHook(to).onTokenReceived();
        }
    }
}

/// @notice MockUSDC that burns 1 unit of every transfer (fee-on-transfer), to hit FundingMismatch.
contract FeeUSDC is MockUSDC {
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0) && value > 0) {
            super._update(from, to, value - 1);
            super._update(from, address(0), 1);
        } else {
            super._update(from, to, value);
        }
    }
}
