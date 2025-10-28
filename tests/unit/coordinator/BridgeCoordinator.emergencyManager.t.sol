// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { BridgeCoordinatorTest } from "../BridgeCoordinator.t.sol";

abstract contract BridgeCoordinator_EmergencyManager_Test is BridgeCoordinatorTest {
    address manager = makeAddr("manager");
    bytes32 managerRole;

    function setUp() public virtual override {
        super.setUp();

        managerRole = coordinator.EMERGENCY_MANAGER_ROLE();
        vm.prank(admin);
        coordinator.grantRole(managerRole, manager);
    }
}

contract BridgeCoordinator_EmergencyManager_ForceRemoveLocalBridgeAdapter_Test is
    BridgeCoordinator_EmergencyManager_Test
{
    function test_shouldRevert_whenCallerNotEmergencyRole() public {
        address caller = makeAddr("notEmergency");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        coordinator.forceRemoveLocalBridgeAdapter(bridgeType);
    }

    function test_shouldRemoveLocalAdapter() public {
        assertEq(address(coordinator.localBridgeAdapter(bridgeType)), localAdapter);

        vm.prank(manager);
        coordinator.forceRemoveLocalBridgeAdapter(bridgeType);

        assertEq(address(coordinator.localBridgeAdapter(bridgeType)), address(0));
    }
}

contract BridgeCoordinator_EmergencyManager_ForceRemoveRemoteBridgeAdapter_Test is
    BridgeCoordinator_EmergencyManager_Test
{
    function test_shouldRevert_whenCallerNotEmergencyRole() public {
        address caller = makeAddr("notEmergency");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        coordinator.forceRemoveRemoteBridgeAdapter(bridgeType, remoteChainId);
    }

    function test_shouldRemoveRemoteAdapter() public {
        assertEq(coordinator.remoteBridgeAdapter(bridgeType, remoteChainId), remoteAdapter);

        vm.prank(manager);
        coordinator.forceRemoveRemoteBridgeAdapter(bridgeType, remoteChainId);

        assertEq(coordinator.remoteBridgeAdapter(bridgeType, remoteChainId), bytes32(0));
    }
}

contract BridgeCoordinator_EmergencyManager_ForceRemoveInboundOnlyLocalBridgeAdapter_Test is
    BridgeCoordinator_EmergencyManager_Test
{
    function test_shouldRevert_whenCallerNotEmergencyRole() public {
        address caller = makeAddr("notEmergency");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        coordinator.forceRemoveInboundOnlyLocalBridgeAdapter(bridgeType, localAdapter);
    }

    function test_shouldRemoveInboundOnlyLocalAdapter() public {
        coordinator.workaround_setIsInboundOnlyLocalBridgeAdapter(bridgeType, localAdapter, true);
        assertTrue(coordinator.isInboundOnlyLocalBridgeAdapter(bridgeType, localAdapter));

        vm.prank(manager);
        coordinator.forceRemoveInboundOnlyLocalBridgeAdapter(bridgeType, localAdapter);

        assertFalse(coordinator.isInboundOnlyLocalBridgeAdapter(bridgeType, localAdapter));
    }
}

contract BridgeCoordinator_EmergencyManager_ForceRemoveInboundOnlyRemoteBridgeAdapter_Test is
    BridgeCoordinator_EmergencyManager_Test
{
    function test_shouldRevert_whenCallerNotEmergencyRole() public {
        address caller = makeAddr("notEmergency");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        coordinator.forceRemoveInboundOnlyRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter);
    }

    function test_shouldRemoveInboundOnlyRemoteAdapter() public {
        coordinator.workaround_setIsInboundOnlyRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter, true);
        assertTrue(coordinator.isInboundOnlyRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter));

        vm.prank(manager);
        coordinator.forceRemoveInboundOnlyRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter);

        assertFalse(coordinator.isInboundOnlyRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter));
    }
}
