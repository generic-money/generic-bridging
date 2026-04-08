// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { BridgeCoordinatorTempo, IERC20, ITIP20Mintable } from "../../src/BridgeCoordinatorTempo.sol";

import { BridgeCoordinatorTempoHarness } from "../harness/BridgeCoordinatorTempoHarness.sol";

abstract contract BridgeCoordinatorTempoTest is Test {
    BridgeCoordinatorTempoHarness coordinator;

    address admin = makeAddr("admin");
    address whitelabel = makeAddr("whitelabel");
    address owner = makeAddr("owner");

    function _resetInitializableStorageSlot() internal {
        // reset the Initializable storage slot to allow usage of deployed instance in tests
        vm.store(address(coordinator), coordinator.exposed_initializableStorageSlot(), bytes32(0));
    }

    function setUp() public virtual {
        coordinator = new BridgeCoordinatorTempoHarness();
        _resetInitializableStorageSlot();
        coordinator.initialize(makeAddr("unit"), admin);

        vm.mockCall(whitelabel, abi.encodeWithSelector(ITIP20Mintable.mint.selector), "");
        vm.mockCall(whitelabel, abi.encodeWithSelector(ITIP20Mintable.burn.selector), "");
        vm.mockCall(whitelabel, abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
    }
}

contract BridgeCoordinatorTempo_RestrictUnits_Test is BridgeCoordinatorTempoTest {
    uint256 initialBalance = 1_000_000 ether;

    function setUp() public override virtual {
        super.setUp();
        coordinator.workaround_setUnitBalanceOf(whitelabel, initialBalance);
    }

    function test_shouldRevert_whenZeroWhitelabel() public {
        vm.expectRevert(BridgeCoordinatorTempo.MissingWhitelabelAddress.selector);
        coordinator.exposed_restrictUnits(address(0), owner, 1);
    }

    function testFuzz_shouldRevert_whenInsufficientUnits(uint256 amount) public {
        amount = bound(amount, initialBalance + 1, type(uint256).max);

        vm.expectRevert(BridgeCoordinatorTempo.InsufficientUnitsToBridgeOut.selector);
        coordinator.exposed_restrictUnits(whitelabel, owner, amount);
    }

    function testFuzz_shouldRevert_whenRoundingToZero(uint256 amount) public {
        amount = bound(amount, 0, 1e12 - 1); // amounts that would round to zero when converting from 18 to 6 decimals

        vm.expectRevert(BridgeCoordinatorTempo.DecimalsRoundingToZero.selector);
        coordinator.exposed_restrictUnits(whitelabel, owner, amount);
    }

    function testFuzz_shouldDecreaseUnitBalance(uint256 amount) public {
        amount = bound(amount, 1e12, initialBalance);

        coordinator.exposed_restrictUnits(whitelabel, owner, amount);

        assertEq(coordinator.unitBalanceOf(whitelabel), initialBalance - amount);
    }

    function testFuzz_shouldTransferAndBurnWhitelabel(uint256 tip20Amount) public {
        tip20Amount = bound(tip20Amount, 1e6, 1_000_000e6);

        vm.expectCall(whitelabel, abi.encodeWithSelector(IERC20.transferFrom.selector, owner, address(coordinator), tip20Amount));
        vm.expectCall(whitelabel, abi.encodeWithSelector(ITIP20Mintable.burn.selector, tip20Amount));

        coordinator.exposed_restrictUnits(whitelabel, owner, tip20Amount * 1e12);
    }
}

contract BridgeCoordinatorTempo_ReleaseUnits_Test is BridgeCoordinatorTempoTest {
    function test_shouldRevert_whenZeroWhitelabel() public {
        vm.expectRevert(BridgeCoordinatorTempo.MissingWhitelabelAddress.selector);
        coordinator.exposed_releaseUnits(address(0), owner, 1);
    }

    function testFuzz_shouldIncreaseUnitBalance(uint256 amount) public {
        amount = bound(amount, 1e12, 1e60);

        uint256 initialBalance = 1_000_000e18;
        coordinator.workaround_setUnitBalanceOf(whitelabel, initialBalance);

        coordinator.exposed_releaseUnits(whitelabel, owner, amount);

        assertEq(coordinator.unitBalanceOf(whitelabel), initialBalance + amount);
    }

    function testFuzz_shouldRevert_whenRoundingToZero(uint256 amount) public {
        amount = bound(amount, 0, 1e12 - 1); // amounts that would round to zero when converting from 18 to 6 decimals

        vm.expectRevert(BridgeCoordinatorTempo.DecimalsRoundingToZero.selector);
        coordinator.exposed_releaseUnits(whitelabel, owner, amount);
    }

    function testFuzz_shouldMintWhitelabel(address receiver, uint256 tip20Amount) public {
        tip20Amount = bound(tip20Amount, 1e6, 1_000_000e6);
        vm.assume(receiver != address(0));

        vm.expectCall(whitelabel, abi.encodeWithSelector(ITIP20Mintable.mint.selector, receiver, tip20Amount));

        coordinator.exposed_releaseUnits(whitelabel, receiver, tip20Amount * 1e12);
    }
}
