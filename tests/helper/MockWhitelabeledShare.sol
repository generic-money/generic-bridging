// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { ERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IWhitelabeledShare } from "../../src/interfaces/IWhitelabeledShare.sol";

contract MockWhitelabeledShare is IWhitelabeledShare, ERC20 {
    address public immutable shareToken;

    bool public revertNextCall;

    constructor(address _shareToken) ERC20("Mock USD", "M-USD") {
        shareToken = _shareToken;
    }

    function wrap(address owner, uint256 amount) external {
        require(!revertNextCall, "MockWhitelabeledShare: revertNextCall is set");
        require(
            IERC20(shareToken).transferFrom(msg.sender, address(this), amount),
            "MockWhitelabeledShare: transferFrom failed"
        );
        _mint(owner, amount);
        emit Wrapped(owner, amount);
    }

    function unwrap(address owner, address recipient, uint256 amount) external {
        require(!revertNextCall, "MockWhitelabeledShare: revertNextCall is set");
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, amount);
        _burn(owner, amount);
        require(IERC20(shareToken).transfer(recipient, amount), "MockWhitelabeledShare: transfer failed");
        emit Unwrapped(owner, recipient, amount);
    }

    function setRevertNextCall(bool _revert) external {
        revertNextCall = _revert;
    }
}
