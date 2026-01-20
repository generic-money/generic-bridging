// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

error MyError();

contract Test {
    function foo(bool ok) external pure {
        require(ok, MyError());
    }
}
