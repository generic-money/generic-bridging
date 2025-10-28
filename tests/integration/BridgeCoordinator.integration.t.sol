// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { BridgeCoordinatorL1, BridgeCoordinator } from "../../src/BridgeCoordinatorL1.sol";
import { PredepositCoordinator } from "../../src/coordinator/PredepositCoordinator.sol";
import { BridgeMessageCoordinator } from "../../src/coordinator/BridgeMessageCoordinator.sol";

import { MockBridgeAdapter } from "../helper/MockBridgeAdapter.sol";
import { MockERC20 } from "../helper/MockERC20.sol";

abstract contract BridgeCoordinatorIntegrationTest is Test {
    BridgeCoordinatorL1 coordinator;
    MockERC20 gusd;

    MockBridgeAdapter localAdapter;
    bytes32 remoteAdapter = keccak256("remote adapter");

    address controller = makeAddr("controller");
    address user = makeAddr("user");
    bytes32 remoteUser = keccak256("remote user");
    address relayer = makeAddr("relayer");
    uint256 chainId = 42;
    uint16 bridgeType = 1;
    bytes32 messageId = keccak256("messageId");

    function setUp() public virtual {
        coordinator = BridgeCoordinatorL1(
            address(new TransparentUpgradeableProxy(address(new BridgeCoordinatorL1()), address(this), ""))
        );
        gusd = new MockERC20(18);
        coordinator.initialize(address(gusd), address(this));

        coordinator.grantRole(coordinator.ADAPTER_MANAGER_ROLE(), address(this));
        coordinator.grantRole(coordinator.PREDEPOSIT_MANAGER_ROLE(), address(this));

        localAdapter = new MockBridgeAdapter(bridgeType, address(coordinator));

        deal(address(gusd), user, 1_000_000e18);
        vm.prank(user);
        gusd.approve(address(coordinator), type(uint256).max);

        deal(user, 10 ether);
        deal(relayer, 10 ether);

        vm.label(address(coordinator), "BridgeCoordinatorL1");
        vm.label(address(controller), "Controller");
        vm.label(address(gusd), "GUSD");
    }
}

contract BridgeCoordinator_Bridge_IntegrationTest is BridgeCoordinatorIntegrationTest {
    function test_bridge_outbound() public {
        // Fail to bridge when no adapters are set
        vm.expectRevert(BridgeCoordinator.NoLocalBridgeAdapter.selector);
        vm.prank(user);
        coordinator.bridge{ value: 1 ether }(bridgeType, chainId, user, remoteUser, 100e18, "bridge data");

        // Setup local adapter
        coordinator.setIsInboundOnlyLocalBridgeAdapter(bridgeType, localAdapter, true);
        coordinator.swapOutboundLocalBridgeAdapter(bridgeType, localAdapter);
        assertFalse(coordinator.supportsBridgeTypeFor(bridgeType, chainId));

        // Fail to bridge when no remote adapter is set
        vm.expectRevert(BridgeCoordinator.NoRemoteBridgeAdapter.selector);
        vm.prank(user);
        coordinator.bridge{ value: 1 ether }(bridgeType, chainId, user, remoteUser, 100e18, "bridge data");

        // Setup remote adapter
        coordinator.setIsInboundOnlyRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter, true);
        coordinator.swapOutboundRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter);
        assertTrue(coordinator.supportsBridgeTypeFor(bridgeType, chainId));

        // Bridge successfully
        localAdapter.returnMessageId(messageId);
        vm.prank(user);
        bytes32 msgId =
            coordinator.bridge{ value: 1 ether }(bridgeType, chainId, user, remoteUser, 100e18, "bridge data");

        assertEq(msgId, messageId);
        assertEq(gusd.balanceOf(address(coordinator)), 100e18);
        bytes memory expectedMessage =
            coordinator.encodeBridgeMessage(coordinator.encodeOmnichainAddress(user), remoteUser, 100e18);
        (
            uint256 chainId_,
            bytes32 remoteAdapter_,
            bytes memory message,
            address refundAddress,
            bytes memory bridgeParams
        ) = localAdapter.lastBridgeCall();
        assertEq(chainId_, chainId, "chain id mismatch");
        assertEq(remoteAdapter_, remoteAdapter, "remote adapter mismatch");
        assertEq(message, expectedMessage, "message mismatch");
        assertEq(refundAddress, user, "refund address mismatch");
        assertEq(bridgeParams, "bridge data", "bridge params mismatch");
    }

    function test_bridge_inbound() public {
        deal(address(gusd), address(coordinator), 100e18); // Pre-fund coordinator for inbound bridge
        address receiver = makeAddr("receiver");
        bytes memory messageData =
            coordinator.encodeBridgeMessage(remoteUser, coordinator.encodeOmnichainAddress(receiver), 100e18);

        // Fail to settle when no adapters are set
        vm.expectRevert(BridgeCoordinator.OnlyLocalAdapter.selector);
        vm.prank(address(localAdapter));
        coordinator.settleInboundMessage(bridgeType, chainId, remoteUser, messageData, messageId);

        // Setup adapters
        coordinator.setIsInboundOnlyLocalBridgeAdapter(bridgeType, localAdapter, true);
        coordinator.swapOutboundLocalBridgeAdapter(bridgeType, localAdapter);
        coordinator.setIsInboundOnlyRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter, true);
        coordinator.swapOutboundRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter);

        // Settle successfully
        vm.prank(address(localAdapter));
        coordinator.settleInboundMessage(bridgeType, chainId, remoteAdapter, messageData, messageId);

        assertEq(gusd.balanceOf(receiver), 100e18);
        assertEq(gusd.balanceOf(address(coordinator)), 0);

        // Store failed message execution for rollback test
        vm.prank(address(localAdapter));
        coordinator.settleInboundMessage(bridgeType, chainId, remoteAdapter, messageData, messageId);

        assertEq(gusd.balanceOf(receiver), 100e18); // still only 100e18
        assertNotEq(coordinator.failedMessageExecutions(messageId), bytes32(0), "failed message execution not stored");
    }

    function test_bridge_rollback() public {
        bytes memory messageData =
            coordinator.encodeBridgeMessage(remoteUser, coordinator.encodeOmnichainAddress(user), 100e18);

        // Setup adapters
        coordinator.setIsInboundOnlyLocalBridgeAdapter(bridgeType, localAdapter, true);
        coordinator.swapOutboundLocalBridgeAdapter(bridgeType, localAdapter);
        coordinator.setIsInboundOnlyRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter, true);
        coordinator.swapOutboundRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter);

        // Store failed message execution (not enough funds)
        vm.prank(address(localAdapter));
        coordinator.settleInboundMessage(bridgeType, chainId, remoteAdapter, messageData, messageId);

        bytes32 failedMessageExecution = coordinator.failedMessageExecutions(messageId);
        assertNotEq(failedMessageExecution, bytes32(0), "failed message execution not stored");

        // Fail to rollback with invalid data
        bytes memory invalidFailedMessageData =
            coordinator.encodeBridgeMessage(remoteUser, coordinator.encodeOmnichainAddress(user), 1000e18);
        vm.expectRevert(BridgeMessageCoordinator.BridgeMessage_InvalidFailedMessageData.selector);
        vm.prank(relayer);
        coordinator.rollback{ value: 1 ether }(bridgeType, chainId, invalidFailedMessageData, messageId, "bridge data");

        // Setup different bridge type
        uint16 bridgeType2 = bridgeType + 1;
        MockBridgeAdapter localAdapter2 = new MockBridgeAdapter(bridgeType2, address(coordinator));
        coordinator.setIsInboundOnlyLocalBridgeAdapter(bridgeType2, localAdapter2, true);
        coordinator.swapOutboundLocalBridgeAdapter(bridgeType2, localAdapter2);
        coordinator.setIsInboundOnlyRemoteBridgeAdapter(bridgeType2, chainId, remoteAdapter, true);
        coordinator.swapOutboundRemoteBridgeAdapter(bridgeType2, chainId, remoteAdapter);
        assertTrue(coordinator.supportsBridgeTypeFor(bridgeType2, chainId));

        // Rollback successfully via different bridge type
        bytes32 rollbackMessageId = keccak256("rollbackMessageId");
        localAdapter2.returnMessageId(rollbackMessageId);
        vm.prank(relayer);
        bytes32 rollbackMsgId = coordinator.rollback{ value: 1 ether }(
            bridgeType2, chainId, messageData, messageId, "rollback bridge data"
        );

        assertEq(rollbackMsgId, rollbackMessageId);
        assertEq(coordinator.failedMessageExecutions(messageId), bytes32(0), "failed message execution not deleted");
        bytes memory expectedRollbackMessage = coordinator.encodeBridgeMessage(bytes32(0), remoteUser, 100e18);
        (
            uint256 chainId_,
            bytes32 remoteAdapter_,
            bytes memory message,
            address refundAddress,
            bytes memory bridgeParams
        ) = localAdapter2.lastBridgeCall();
        assertEq(chainId_, chainId, "chain id mismatch");
        assertEq(remoteAdapter_, remoteAdapter, "remote adapter mismatch");
        assertEq(message, expectedRollbackMessage, "message mismatch");
        assertEq(refundAddress, relayer, "refund address mismatch");
        assertEq(bridgeParams, "rollback bridge data", "bridge params mismatch");
    }
}

contract BridgeCoordinator_Predeposit_IntegrationTest is BridgeCoordinatorIntegrationTest {
    bytes32 chainNickname = keccak256("super duper L2 chain");

    function test_predeposit_dispatch() public {
        // Fail to predeposit before enabling
        vm.expectRevert(PredepositCoordinator.Predeposit_NotEnabled.selector);
        vm.prank(user);
        coordinator.predeposit(chainNickname, user, remoteUser, 100e18);

        // Enable predeposits for a chain
        coordinator.enablePredeposits(chainNickname);
        assertEq(
            uint8(coordinator.getChainPredepositState(chainNickname)),
            uint8(PredepositCoordinator.PredepositState.ENABLED)
        );

        // Predeposit successfully
        vm.prank(user);
        coordinator.predeposit(chainNickname, user, remoteUser, 100e18);

        assertEq(gusd.balanceOf(address(coordinator)), 100e18);
        assertEq(coordinator.getPredeposit(chainNickname, user, remoteUser), 100e18);

        // Predeposit more successfully
        vm.prank(user);
        coordinator.predeposit(chainNickname, user, remoteUser, 300e18);

        assertEq(gusd.balanceOf(address(coordinator)), 400e18);
        assertEq(coordinator.getPredeposit(chainNickname, user, remoteUser), 400e18);

        // Enable dispatch for a chain
        coordinator.enablePredepositsDispatch(chainNickname, chainId);
        assertEq(
            uint8(coordinator.getChainPredepositState(chainNickname)),
            uint8(PredepositCoordinator.PredepositState.DISPATCHED)
        );
        assertEq(coordinator.getChainIdForNickname(chainNickname), chainId);

        // Fail to withdraw after enabling dispatch
        vm.expectRevert(PredepositCoordinator.Predeposit_WithdrawalsNotEnabled.selector);
        vm.prank(user);
        coordinator.withdrawPredeposit(chainNickname, remoteUser, user);

        // Fail to dispatch when no adapters are set
        vm.expectRevert(BridgeCoordinator.NoLocalBridgeAdapter.selector);
        vm.prank(relayer);
        coordinator.bridgePredeposit{ value: 1 ether }(bridgeType, chainNickname, user, remoteUser, "");

        // Setup adapters
        assertFalse(coordinator.supportsBridgeTypeFor(bridgeType, chainId));
        coordinator.setIsInboundOnlyLocalBridgeAdapter(bridgeType, localAdapter, true);
        coordinator.setIsInboundOnlyRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter, true);
        coordinator.swapOutboundLocalBridgeAdapter(bridgeType, localAdapter);
        coordinator.swapOutboundRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter);
        assertTrue(coordinator.supportsBridgeTypeFor(bridgeType, chainId));

        // Dispatch successfully
        localAdapter.returnMessageId(messageId);
        vm.prank(relayer);
        bytes32 msgId =
            coordinator.bridgePredeposit{ value: 1 ether }(bridgeType, chainNickname, user, remoteUser, "bridge data");

        assertEq(msgId, messageId);
        assertEq(gusd.balanceOf(address(coordinator)), 400e18);
        assertEq(coordinator.getPredeposit(chainNickname, user, remoteUser), 0);
        bytes memory expectedMessage =
            coordinator.encodeBridgeMessage(coordinator.encodeOmnichainAddress(user), remoteUser, 400e18);
        (
            uint256 chainId_,
            bytes32 remoteAdapter_,
            bytes memory message,
            address refundAddress,
            bytes memory bridgeParams
        ) = localAdapter.lastBridgeCall();
        assertEq(chainId_, chainId, "chain id mismatch");
        assertEq(remoteAdapter_, remoteAdapter, "remote adapter mismatch");
        assertEq(message, expectedMessage, "message mismatch");
        assertEq(refundAddress, relayer, "refund address mismatch");
        assertEq(bridgeParams, "bridge data", "bridge params mismatch");

        // Fail to predeposit after enabling dispatch
        vm.expectRevert(PredepositCoordinator.Predeposit_NotEnabled.selector);
        vm.prank(user);
        coordinator.predeposit(chainNickname, user, remoteUser, 100e18);
    }

    function test_predeposit_withdraw() public {
        // Enable predeposits for a chain
        coordinator.enablePredeposits(chainNickname);

        // Predeposit successfully
        vm.prank(user);
        coordinator.predeposit(chainNickname, user, remoteUser, 100e18);

        // Enable withdrawals for a chain
        coordinator.enablePredepositsWithdraw(chainNickname);
        assertEq(
            uint8(coordinator.getChainPredepositState(chainNickname)),
            uint8(PredepositCoordinator.PredepositState.WITHDRAWN)
        );
        assertEq(coordinator.getChainIdForNickname(chainNickname), 0);

        // Fail to dispatch after enabling withdrawals
        vm.expectRevert(PredepositCoordinator.Predeposit_DispatchNotEnabled.selector);
        vm.prank(relayer);
        coordinator.bridgePredeposit{ value: 1 ether }(bridgeType, chainNickname, user, remoteUser, "");

        // Withdraw successfully
        vm.prank(user);
        coordinator.withdrawPredeposit(chainNickname, remoteUser, user);

        assertEq(gusd.balanceOf(address(coordinator)), 0);
        assertEq(coordinator.getPredeposit(chainNickname, user, remoteUser), 0);

        // Fail to predeposit after enabling withdrawals
        vm.expectRevert(PredepositCoordinator.Predeposit_NotEnabled.selector);
        vm.prank(user);
        coordinator.predeposit(chainNickname, user, remoteUser, 100e18);
    }
}
