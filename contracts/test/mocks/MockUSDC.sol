// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice 6-decimal USDC mock with a blocklist. transfer/transferFrom to or from a blocked
///         address reverts (mint and burn are not affected).
contract MockUSDC is ERC20 {
    error Blocked(address account);

    mapping(address => bool) public blocked;

    constructor() ERC20("Mock USDC", "mUSDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setBlocked(address account, bool isBlocked) external {
        blocked[account] = isBlocked;
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0) && to != address(0)) {
            if (blocked[from]) revert Blocked(from);
            if (blocked[to]) revert Blocked(to);
        }
        super._update(from, to, value);
    }
}
