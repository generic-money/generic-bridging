// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { BridgeCoordinatorTempo, ITIP20 } from "../../src/chains/tempo/BridgeCoordinatorTempo.sol";
import { BaseBridgeCoordinatorHarness } from "../harness/BaseBridgeCoordinatorHarness.sol";

contract BridgeCoordinatorTempoHarness is BaseBridgeCoordinatorHarness, BridgeCoordinatorTempo { }

abstract contract BridgeCoordinatorTempoTest is Test {
    BridgeCoordinatorTempoHarness coordinator;

    address unit = makeAddr("unit");
    address admin = makeAddr("admin");
    address whitelabel = makeAddr("whitelabel");

    function _resetInitializableStorageSlot() internal {
        // reset the Initializable storage slot to allow usage of deployed instance in tests
        vm.store(address(coordinator), coordinator.exposed_initializableStorageSlot(), bytes32(0));
    }

    function setUp() public virtual {
        coordinator = new BridgeCoordinatorTempoHarness();
        _resetInitializableStorageSlot();
        coordinator.initialize(unit, admin);

        vm.mockCall(unit, abi.encodeWithSelector(ITIP20.transferFrom.selector), abi.encode(true));
        vm.mockCall(unit, abi.encodeWithSelector(ITIP20.burn.selector), "");
        vm.mockCall(unit, abi.encodeWithSelector(ITIP20.mint.selector), "");
    }
}

contract BridgeCoordinatorTempo_RestrictUnits_Test is BridgeCoordinatorTempoTest {
    function testFuzz_shouldBurnUnits_whenZeroWhitelabel(address owner, uint256 amount) public {
        vm.assume(owner != address(0));
        amount = bound(amount, 1, type(uint256).max / 2);

        bytes[] memory returnData = new bytes[](2);
        returnData[0] = abi.encode(1000e18);
        returnData[1] = abi.encode(1000e18 + amount);
        vm.mockCalls(unit, abi.encodeCall(ITIP20.balanceOf, (address(coordinator))), returnData);

        vm.expectCall(unit, abi.encodeCall(ITIP20.transferFrom, (owner, address(coordinator), amount)));
        vm.expectCall(unit, abi.encodeCall(ITIP20.burn, (amount)));

        coordinator.exposed_restrictUnits(address(0), owner, amount);
    }

    function test_shouldRevert_whenTransferCreditsLessThanRequestedAmount() public {
        address owner = makeAddr("owner");
        uint256 amount = 500;

        bytes[] memory returnData = new bytes[](2);
        returnData[0] = abi.encode(1000e18);
        returnData[1] = abi.encode(1000e18 + amount - 1);
        vm.mockCalls(unit, abi.encodeCall(ITIP20.balanceOf, (address(coordinator))), returnData);
        vm.mockCallRevert(
            unit,
            abi.encodeCall(ITIP20.burn, (amount)),
            abi.encodeWithSignature("Error(string)", "burn should not be called")
        );

        vm.expectRevert(BridgeCoordinatorTempo.IncorrectEscrowBalance.selector);
        coordinator.exposed_restrictUnits(address(0), owner, amount);
    }

    function test_shouldRevert_whenTransferCreditsMoreThanRequestedAmount() public {
        address owner = makeAddr("owner");
        uint256 amount = 500;

        bytes[] memory returnData = new bytes[](2);
        returnData[0] = abi.encode(1000e18);
        returnData[1] = abi.encode(1000e18 + amount + 1);
        vm.mockCalls(unit, abi.encodeCall(ITIP20.balanceOf, (address(coordinator))), returnData);
        vm.mockCallRevert(
            unit,
            abi.encodeCall(ITIP20.burn, (amount)),
            abi.encodeWithSignature("Error(string)", "burn should not be called")
        );

        vm.expectRevert(BridgeCoordinatorTempo.IncorrectEscrowBalance.selector);
        coordinator.exposed_restrictUnits(address(0), owner, amount);
    }

    function test_shouldRevert_whenWhitelabelIsProvided() public {
        vm.expectRevert(BridgeCoordinatorTempo.WhitelabelsNotSupported.selector);
        coordinator.exposed_restrictUnits(whitelabel, makeAddr("owner"), 1);
    }
}
