// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { ITIP20Mintable } from "../../src/interfaces/ITIP20Mintable.sol";

import { MockERC20 } from "./MockERC20.sol";

contract MockTIP20 is MockERC20, ITIP20Mintable {
    bool public revertNextCall;

    constructor() MockERC20(6) { }

    function mint(address to, uint256 amount) external override(MockERC20, ITIP20Mintable) {
        require(!revertNextCall, "MockTIP20: revertNextCall is set");
        _mint(to, amount);
        emit Mint(to, amount);
    }

    function burn(uint256 amount) external {
        require(!revertNextCall, "MockTIP20: revertNextCall is set");
        _burn(msg.sender, amount);
        emit Burn(msg.sender, amount);
    }

    function setRevertNextCall(bool _revert) external {
        revertNextCall = _revert;
    }
}
