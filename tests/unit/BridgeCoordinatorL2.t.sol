// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { IERC20Mintable, IWhitelabeledShare } from "../../src/BridgeCoordinatorL2.sol";

import { BridgeCoordinatorL2Harness } from "../harness/BridgeCoordinatorL2Harness.sol";

abstract contract BridgeCoordinatorL2Test is Test {
    BridgeCoordinatorL2Harness coordinator;

    address share = makeAddr("share");
    address admin = makeAddr("admin");
    address whitelabel = makeAddr("whitelabel");

    function _resetInitializableStorageSlot() internal {
        // reset the Initializable storage slot to allow usage of deployed instance in tests
        vm.store(address(coordinator), coordinator.exposed_initializableStorageSlot(), bytes32(0));
    }

    function setUp() public virtual {
        coordinator = new BridgeCoordinatorL2Harness();
        _resetInitializableStorageSlot();
        coordinator.initialize(share, admin);

        vm.mockCall(share, abi.encodeWithSelector(IERC20Mintable.mint.selector), "");
        vm.mockCall(share, abi.encodeWithSelector(IERC20Mintable.burn.selector), "");
        vm.mockCall(whitelabel, abi.encodeWithSelector(IWhitelabeledShare.wrap.selector), "");
        vm.mockCall(whitelabel, abi.encodeWithSelector(IWhitelabeledShare.unwrap.selector), "");
    }
}

contract BridgeCoordinatorL2_RestrictShares_Test is BridgeCoordinatorL2Test {
    function testFuzz_shouldBurnTokens_whenZeroWhitelabel(address owner, uint256 amount) public {
        vm.assume(owner != address(0));
        vm.assume(amount > 0);

        vm.expectCall(share, abi.encodeWithSelector(IERC20Mintable.burn.selector, owner, address(coordinator), amount));

        coordinator.exposed_restrictShares(address(0), owner, amount);
    }

    function testFuzz_shouldUnwrapAndBurnTokens_whenWhitelabel(address owner, uint256 amount) public {
        vm.assume(owner != address(0));
        vm.assume(amount > 0);

        vm.expectCall(whitelabel, abi.encodeCall(IWhitelabeledShare.unwrap, (owner, address(coordinator), amount)));
        vm.expectCall(share, abi.encodeCall(IERC20Mintable.burn, (address(coordinator), address(coordinator), amount)));

        coordinator.exposed_restrictShares(whitelabel, owner, amount);
    }
}

contract BridgeCoordinatorL2_ReleaseShares_Test is BridgeCoordinatorL2Test {
    function testFuzz_shouldMintTokens_whenZeroWhitelabel(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0));
        vm.assume(amount > 0);

        vm.expectCall(share, abi.encodeWithSelector(IERC20Mintable.mint.selector, recipient, amount));

        coordinator.exposed_releaseShares(address(0), recipient, amount);
    }

    function testFuzz_shouldMintAndWrapTokens_whenWhitelabel(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0));
        vm.assume(amount > 0);

        vm.expectCall(share, abi.encodeCall(IERC20Mintable.mint, (address(coordinator), amount)));
        vm.expectCall(whitelabel, abi.encodeCall(IWhitelabeledShare.wrap, (recipient, amount)));

        coordinator.exposed_releaseShares(whitelabel, recipient, amount);
    }
}
