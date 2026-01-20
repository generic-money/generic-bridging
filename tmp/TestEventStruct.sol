// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

struct MyStruct { uint256 a; }

contract Test {
    event MyEvent(MyStruct value);

    function emitEvent() external {
        emit MyEvent(MyStruct({a: 1}));
    }
}
