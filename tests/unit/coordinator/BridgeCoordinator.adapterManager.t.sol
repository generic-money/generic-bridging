// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { AdapterManager, IBridgeAdapter } from "../../../src/coordinator/BridgeCoordinator.sol";

import { BridgeCoordinatorTest } from "./BridgeCoordinator.t.sol";

abstract contract BridgeCoordinator_AdapterManager_Test is BridgeCoordinatorTest {
    address manager = makeAddr("manager");
    bytes32 managerRole;

    function setUp() public virtual override {
        super.setUp();

        managerRole = coordinator.ADAPTER_MANAGER_ROLE();
        vm.prank(admin);
        coordinator.grantRole(managerRole, manager);
    }
}

contract BridgeCoordinator_AdapterManager_SetIsInboundOnlyLocalBridgeAdapter_Test is
    BridgeCoordinator_AdapterManager_Test
{
    address newAdapter = makeAddr("newAdapter");

    function setUp() public override {
        super.setUp();

        vm.mockCall(
            newAdapter,
            abi.encodeWithSelector(IBridgeAdapter.bridgeCoordinator.selector),
            abi.encode(address(coordinator))
        );
        vm.mockCall(newAdapter, abi.encodeWithSelector(IBridgeAdapter.bridgeType.selector), abi.encode(bridgeType));
    }

    function test_shouldRevert_whenCallerNotManager() public {
        address caller = makeAddr("notManager");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        coordinator.setIsInboundOnlyLocalBridgeAdapter(bridgeType, IBridgeAdapter(newAdapter), true);
    }

    function testFuzz_shouldRevert_whenCoordinatorMismatch_whenAdding(address notCoordinator) public {
        vm.assume(notCoordinator != address(coordinator));

        vm.mockCall(
            newAdapter, abi.encodeWithSelector(IBridgeAdapter.bridgeCoordinator.selector), abi.encode(notCoordinator)
        );

        vm.expectRevert(AdapterManager.CoordinatorMismatch.selector);
        vm.prank(manager);
        coordinator.setIsInboundOnlyLocalBridgeAdapter(bridgeType, IBridgeAdapter(newAdapter), true);
    }

    function testFuzz_shouldRevert_whenBridgeTypeMismatch_whenAdding(uint16 badBridgeType) public {
        vm.assume(badBridgeType != bridgeType);

        vm.mockCall(newAdapter, abi.encodeWithSelector(IBridgeAdapter.bridgeType.selector), abi.encode(badBridgeType));

        vm.expectRevert(AdapterManager.BridgeTypeMismatch.selector);
        vm.prank(manager);
        coordinator.setIsInboundOnlyLocalBridgeAdapter(bridgeType, IBridgeAdapter(newAdapter), true);
    }

    function testFuzz_shouldSetNewAdapter(uint16 _bridgeType, address _newAdapter) public {
        vm.assume(_newAdapter != address(0));
        vm.assume(_newAdapter != VM_ADDRESS);

        vm.mockCall(
            _newAdapter,
            abi.encodeWithSelector(IBridgeAdapter.bridgeCoordinator.selector),
            abi.encode(address(coordinator))
        );
        vm.mockCall(_newAdapter, abi.encodeWithSelector(IBridgeAdapter.bridgeType.selector), abi.encode(_bridgeType));

        vm.expectEmit();
        emit AdapterManager.LocalInboundOnlyBridgeAdapterUpdated(_bridgeType, _newAdapter, true);

        vm.prank(manager);
        coordinator.setIsInboundOnlyLocalBridgeAdapter(_bridgeType, IBridgeAdapter(_newAdapter), true);

        assertTrue(coordinator.isInboundOnlyLocalBridgeAdapter(_bridgeType, _newAdapter));

        vm.expectEmit();
        emit AdapterManager.LocalInboundOnlyBridgeAdapterUpdated(_bridgeType, _newAdapter, false);

        vm.prank(manager);
        coordinator.setIsInboundOnlyLocalBridgeAdapter(_bridgeType, IBridgeAdapter(_newAdapter), false);

        assertFalse(coordinator.isInboundOnlyLocalBridgeAdapter(_bridgeType, _newAdapter));
    }
}

contract BridgeCoordinator_AdapterManager_SetIsInboundOnlyRemoteBridgeAdapter_Test is
    BridgeCoordinator_AdapterManager_Test
{
    bytes32 newAdapter = bytes32(uint256(uint160(makeAddr("newAdapter"))));

    function test_shouldRevert_whenCallerNotManager() public {
        address caller = makeAddr("notManager");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        coordinator.setIsInboundOnlyRemoteBridgeAdapter(bridgeType, remoteChainId, newAdapter, true);
    }

    function testFuzz_shouldSetNewAdapter_whenAdding(
        uint16 _bridgeType,
        uint256 _chainId,
        address _newAdapter
    )
        public
    {
        vm.assume(_newAdapter != address(0));
        newAdapter = bytes32(uint256(uint160(_newAdapter)));

        vm.expectEmit();
        emit AdapterManager.RemoteInboundOnlyBridgeAdapterUpdated(_bridgeType, _chainId, newAdapter, true);

        vm.prank(manager);
        coordinator.setIsInboundOnlyRemoteBridgeAdapter(_bridgeType, _chainId, newAdapter, true);

        assertTrue(coordinator.isInboundOnlyRemoteBridgeAdapter(_bridgeType, _chainId, newAdapter));

        vm.expectEmit();
        emit AdapterManager.RemoteInboundOnlyBridgeAdapterUpdated(_bridgeType, _chainId, newAdapter, false);

        vm.prank(manager);
        coordinator.setIsInboundOnlyRemoteBridgeAdapter(_bridgeType, _chainId, newAdapter, false);

        assertFalse(coordinator.isInboundOnlyRemoteBridgeAdapter(_bridgeType, _chainId, newAdapter));
    }
}

contract BridgeCoordinator_AdapterManager_SwapOutboundLocalBridgeAdapter_Test is BridgeCoordinator_AdapterManager_Test {
    address newAdapter = makeAddr("newAdapter");

    function setUp() public override {
        super.setUp();

        coordinator.workaround_setIsInboundOnlyLocalBridgeAdapter(bridgeType, newAdapter, true);
    }

    function test_shouldRevert_whenCallerNotManager() public {
        address caller = makeAddr("notManager");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        coordinator.swapOutboundLocalBridgeAdapter(bridgeType, IBridgeAdapter(newAdapter));
    }

    function test_shouldRevert_whenAdapterNotInInboundList() public {
        coordinator.workaround_setIsInboundOnlyLocalBridgeAdapter(bridgeType, newAdapter, false);

        vm.expectRevert(AdapterManager.AdapterNotInInboundList.selector);
        vm.prank(manager);
        coordinator.swapOutboundLocalBridgeAdapter(bridgeType, IBridgeAdapter(newAdapter));
    }

    function test_shouldSwapAdapters() public {
        assertEq(address(coordinator.localBridgeAdapter(bridgeType)), localAdapter);
        assertFalse(coordinator.isInboundOnlyLocalBridgeAdapter(bridgeType, localAdapter));
        assertTrue(coordinator.isInboundOnlyLocalBridgeAdapter(bridgeType, newAdapter));

        vm.expectEmit();
        emit AdapterManager.LocalInboundOnlyBridgeAdapterUpdated(bridgeType, newAdapter, false);
        vm.expectEmit();
        emit AdapterManager.LocalInboundOnlyBridgeAdapterUpdated(bridgeType, localAdapter, true);
        vm.expectEmit();
        emit AdapterManager.LocalOutboundBridgeAdapterUpdated(bridgeType, newAdapter);

        vm.prank(manager);
        coordinator.swapOutboundLocalBridgeAdapter(bridgeType, IBridgeAdapter(newAdapter));

        assertEq(address(coordinator.localBridgeAdapter(bridgeType)), newAdapter);
        assertTrue(coordinator.isInboundOnlyLocalBridgeAdapter(bridgeType, localAdapter));
        assertFalse(coordinator.isInboundOnlyLocalBridgeAdapter(bridgeType, newAdapter));
    }

    function test_shouldRemoveAdapter() public {
        assertEq(address(coordinator.localBridgeAdapter(bridgeType)), localAdapter);
        assertFalse(coordinator.isInboundOnlyLocalBridgeAdapter(bridgeType, localAdapter));

        vm.expectEmit();
        emit AdapterManager.LocalInboundOnlyBridgeAdapterUpdated(bridgeType, localAdapter, true);
        vm.expectEmit();
        emit AdapterManager.LocalOutboundBridgeAdapterUpdated(bridgeType, address(0));

        vm.prank(manager);
        coordinator.swapOutboundLocalBridgeAdapter(bridgeType, IBridgeAdapter(address(0)));

        assertEq(address(coordinator.localBridgeAdapter(bridgeType)), address(0));
        assertTrue(coordinator.isInboundOnlyLocalBridgeAdapter(bridgeType, localAdapter));
    }
}

contract BridgeCoordinator_AdapterManager_SwapOutboundRemoteBridgeAdapter_Test is
    BridgeCoordinator_AdapterManager_Test
{
    bytes32 newAdapter = bytes32(uint256(uint160(makeAddr("newAdapter"))));

    function setUp() public override {
        super.setUp();

        coordinator.workaround_setIsInboundOnlyRemoteBridgeAdapter(bridgeType, remoteChainId, newAdapter, true);
    }

    function test_shouldRevert_whenCallerNotManager() public {
        address caller = makeAddr("notManager");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        coordinator.swapOutboundRemoteBridgeAdapter(bridgeType, remoteChainId, newAdapter);
    }

    function test_shouldRevert_whenAdapterNotInInboundList() public {
        coordinator.workaround_setIsInboundOnlyRemoteBridgeAdapter(bridgeType, remoteChainId, newAdapter, false);

        vm.expectRevert(AdapterManager.AdapterNotInInboundList.selector);
        vm.prank(manager);
        coordinator.swapOutboundRemoteBridgeAdapter(bridgeType, remoteChainId, newAdapter);
    }

    function test_shouldSwapAdapters() public {
        assertEq(coordinator.remoteBridgeAdapter(bridgeType, remoteChainId), remoteAdapter);
        assertFalse(coordinator.isInboundOnlyRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter));
        assertTrue(coordinator.isInboundOnlyRemoteBridgeAdapter(bridgeType, remoteChainId, newAdapter));

        vm.expectEmit();
        emit AdapterManager.RemoteInboundOnlyBridgeAdapterUpdated(bridgeType, remoteChainId, newAdapter, false);
        vm.expectEmit();
        emit AdapterManager.RemoteInboundOnlyBridgeAdapterUpdated(bridgeType, remoteChainId, remoteAdapter, true);
        vm.expectEmit();
        emit AdapterManager.RemoteOutboundBridgeAdapterUpdated(bridgeType, remoteChainId, newAdapter);

        vm.prank(manager);
        coordinator.swapOutboundRemoteBridgeAdapter(bridgeType, remoteChainId, newAdapter);

        assertEq(coordinator.remoteBridgeAdapter(bridgeType, remoteChainId), newAdapter);
        assertTrue(coordinator.isInboundOnlyRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter));
        assertFalse(coordinator.isInboundOnlyRemoteBridgeAdapter(bridgeType, remoteChainId, newAdapter));
    }

    function test_shouldRemoveAdapter() public {
        assertEq(coordinator.remoteBridgeAdapter(bridgeType, remoteChainId), remoteAdapter);
        assertFalse(coordinator.isInboundOnlyRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter));

        vm.expectEmit();
        emit AdapterManager.RemoteInboundOnlyBridgeAdapterUpdated(bridgeType, remoteChainId, remoteAdapter, true);
        vm.expectEmit();
        emit AdapterManager.RemoteOutboundBridgeAdapterUpdated(bridgeType, remoteChainId, bytes32(0));

        vm.prank(manager);
        coordinator.swapOutboundRemoteBridgeAdapter(bridgeType, remoteChainId, bytes32(0));

        assertEq(coordinator.remoteBridgeAdapter(bridgeType, remoteChainId), bytes32(0));
        assertTrue(coordinator.isInboundOnlyRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter));
    }
}
