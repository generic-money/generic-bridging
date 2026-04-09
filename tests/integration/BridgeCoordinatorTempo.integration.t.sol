// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { BridgeCoordinatorTempo, BridgeCoordinator } from "../../src/BridgeCoordinatorTempo.sol";
import { BridgeMessageCoordinator, BridgeMessage } from "../../src/coordinator/BridgeMessageCoordinator.sol";

import { MockBridgeAdapterTokenFee } from "../helper/MockBridgeAdapterTokenFee.sol";
import { MockERC20 } from "../helper/MockERC20.sol";
import { MockTIP20 } from "../helper/MockTIP20.sol";

contract BridgeCoordinatorTempoIntegrationHarness is BridgeCoordinatorTempo {
    // forge-lint: disable-next-line(mixed-case-function)
    function workaround_setUnitBalanceOf(address token, uint256 balance) external {
        unitBalanceOf[token] = balance;
    }
}

abstract contract BridgeCoordinatorTempoIntegrationTest is Test {
    BridgeCoordinatorTempoIntegrationHarness coordinator;
    MockTIP20 gusd;
    MockERC20 feeToken;

    MockBridgeAdapterTokenFee localAdapter;
    bytes32 remoteAdapter = keccak256("remote adapter");

    address controller = makeAddr("controller");
    address user = makeAddr("user");
    bytes32 remoteUser = keccak256("remote user");
    address relayer = makeAddr("relayer");
    uint256 chainId = 42;
    uint16 bridgeType = 1;
    bytes32 destWhitelabel = keccak256("destWhitelabel");
    bytes32 messageId = keccak256("messageId");

    function setUp() public virtual {
        coordinator = BridgeCoordinatorTempoIntegrationHarness(
            address(new TransparentUpgradeableProxy(address(new BridgeCoordinatorTempoIntegrationHarness()), address(this), ""))
        );
        coordinator.initialize(address(0), address(this));

        feeToken = new MockERC20(18);
        gusd = new MockTIP20();

        coordinator.grantRole(coordinator.ADAPTER_MANAGER_ROLE(), address(this));

        localAdapter = new MockBridgeAdapterTokenFee(bridgeType, address(coordinator), address(feeToken));

        coordinator.workaround_setUnitBalanceOf(address(gusd), 1_000_000e18);

        deal(address(gusd), user, 1_000_000e6, true);
        deal(address(feeToken), user, 10 ether, true);
        deal(address(feeToken), relayer, 10 ether, true);

        vm.startPrank(user);
        feeToken.approve(address(coordinator), type(uint256).max);
        gusd.approve(address(coordinator), type(uint256).max);
        vm.stopPrank();

        vm.prank(relayer);
        feeToken.approve(address(coordinator), type(uint256).max);

        vm.label(address(coordinator), "BridgeCoordinatorTempo");
        vm.label(address(controller), "Controller");
        vm.label(address(feeToken), "feeToken");
        vm.label(address(gusd), "GUSD");
    }
}

contract BridgeCoordinatorTempo_Bridge_IntegrationTest is BridgeCoordinatorTempoIntegrationTest {
    function test_bridge_outbound() public {
        // Fail to bridge when no adapters are set
        vm.expectRevert(BridgeCoordinator.NoOutboundLocalBridgeAdapter.selector);
        vm.prank(user);
        coordinator.bridge(
            bridgeType, chainId, user, remoteUser, address(gusd), destWhitelabel, 100e18, "bridge data", 1 ether
        );

        // Setup local adapter
        coordinator.setIsLocalBridgeAdapter(bridgeType, localAdapter, true);
        coordinator.setOutboundLocalBridgeAdapter(bridgeType, localAdapter);
        assertFalse(coordinator.supportsBridgeTypeFor(bridgeType, chainId));

        // Fail to bridge when no remote adapter is set
        vm.expectRevert(BridgeCoordinator.NoOutboundRemoteBridgeAdapter.selector);
        vm.prank(user);
        coordinator.bridge(
            bridgeType, chainId, user, remoteUser, address(gusd), destWhitelabel, 100e18, "bridge data", 1 ether
        );

        // Setup remote adapter
        coordinator.setIsRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter, true);
        coordinator.setOutboundRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter);
        assertTrue(coordinator.supportsBridgeTypeFor(bridgeType, chainId));

        // Bridge successfully
        uint256 preTotalSupply = coordinator.unitBalanceOf(address(gusd)) / 1e12;
        assertEq(gusd.totalSupply(), preTotalSupply);
        assertEq(gusd.balanceOf(user), preTotalSupply);

        vm.prank(user);
        bytes32 msgId = coordinator.bridge(
            bridgeType, chainId, user, remoteUser, address(gusd), destWhitelabel, 100e18, "bridge data", 1 ether
        );

        assertEq(coordinator.unitBalanceOf(address(gusd)), preTotalSupply * 1e12 - 100e18);
        assertEq(gusd.totalSupply(), preTotalSupply - 100e6);
        assertEq(gusd.balanceOf(user), preTotalSupply - 100e6);

        bytes memory expectedMessage = coordinator.encodeBridgeMessage(
            BridgeMessage({
                sender: coordinator.encodeOmnichainAddress(user),
                recipient: remoteUser,
                sourceWhitelabel: coordinator.encodeOmnichainAddress(address(gusd)),
                destinationWhitelabel: destWhitelabel,
                amount: 100e18
            })
        );
        (
            uint256 chainId_,
            bytes32 remoteAdapter_,
            bytes memory message,
            address refundAddress,
            bytes memory bridgeParams,
            bytes32 messageId_
        ) = localAdapter.lastBridgeCall();
        assertEq(chainId_, chainId, "chain id mismatch");
        assertEq(remoteAdapter_, remoteAdapter, "remote adapter mismatch");
        assertEq(message, expectedMessage, "message mismatch");
        assertEq(refundAddress, user, "refund address mismatch");
        assertEq(bridgeParams, "bridge data", "bridge params mismatch");
        assertEq(messageId_, msgId, "message id mismatch");
    }

    function test_bridge_inbound() public {
        address receiver = makeAddr("receiver");
        bytes memory messageData = coordinator.encodeBridgeMessage(
            BridgeMessage({
                sender: remoteUser,
                recipient: coordinator.encodeOmnichainAddress(receiver),
                sourceWhitelabel: coordinator.encodeOmnichainAddress(address(0)),
                destinationWhitelabel: coordinator.encodeOmnichainAddress(address(gusd)),
                amount: 100e18
            })
        );

        // Fail to settle when no adapters are set
        vm.expectRevert(BridgeCoordinator.OnlyLocalAdapter.selector);
        vm.prank(address(localAdapter));
        coordinator.settleInboundMessage(bridgeType, chainId, remoteUser, messageData, messageId);

        // Setup adapters
        coordinator.setIsLocalBridgeAdapter(bridgeType, localAdapter, true);
        coordinator.setOutboundLocalBridgeAdapter(bridgeType, localAdapter);
        coordinator.setIsRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter, true);
        coordinator.setOutboundRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter);

        // Settle successfully
        uint256 preTotalSupply = coordinator.unitBalanceOf(address(gusd)) / 1e12;
        assertEq(gusd.totalSupply(), preTotalSupply);
        assertEq(gusd.balanceOf(receiver), 0);

        vm.prank(address(localAdapter));
        coordinator.settleInboundMessage(bridgeType, chainId, remoteAdapter, messageData, messageId);

        assertEq(coordinator.unitBalanceOf(address(gusd)), preTotalSupply * 1e12 + 100e18);
        assertEq(gusd.totalSupply(), preTotalSupply + 100e6);
        assertEq(gusd.balanceOf(receiver), 100e6);

        // Fail to settle and store failed message execution for rollback test
        gusd.setRevertNextCall(true);

        vm.prank(address(localAdapter));
        coordinator.settleInboundMessage(bridgeType, chainId, remoteAdapter, messageData, messageId);

        assertEq(gusd.balanceOf(receiver), 100e6); // still only 100e6
        assertNotEq(coordinator.failedMessageExecutions(messageId), bytes32(0), "failed message execution not stored");
    }

    function test_bridge_rollback() public {
        BridgeMessage memory message = BridgeMessage({
            sender: remoteUser,
            recipient: coordinator.encodeOmnichainAddress(user),
            sourceWhitelabel: coordinator.encodeOmnichainAddress(address(gusd)),
            destinationWhitelabel: coordinator.encodeOmnichainAddress(address(gusd)),
            amount: 100e18
        });
        bytes memory messageData = coordinator.encodeBridgeMessage(message);

        // Setup adapters
        coordinator.setIsLocalBridgeAdapter(bridgeType, localAdapter, true);
        coordinator.setOutboundLocalBridgeAdapter(bridgeType, localAdapter);
        coordinator.setIsRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter, true);
        coordinator.setOutboundRemoteBridgeAdapter(bridgeType, chainId, remoteAdapter);

        // Fail to settle and store failed message execution for rollback test
        gusd.setRevertNextCall(true);

        vm.prank(address(localAdapter));
        coordinator.settleInboundMessage(bridgeType, chainId, remoteAdapter, messageData, messageId);

        bytes32 failedMessageExecution = coordinator.failedMessageExecutions(messageId);
        assertNotEq(failedMessageExecution, bytes32(0), "failed message execution not stored");

        // Fail to rollback with invalid data
        message.amount = 1000e18; // different amount
        bytes memory invalidFailedMessageData = coordinator.encodeBridgeMessage(message);
        vm.expectRevert(BridgeMessageCoordinator.BridgeMessage_InvalidFailedMessageData.selector);
        vm.prank(relayer);
        coordinator.rollback(bridgeType, chainId, invalidFailedMessageData, messageId, "bridge data", 1 ether);

        // Setup different bridge type
        uint16 bridgeType2 = bridgeType + 1;
        MockBridgeAdapterTokenFee localAdapter2 =
            new MockBridgeAdapterTokenFee(bridgeType2, address(coordinator), address(feeToken));
        coordinator.setIsLocalBridgeAdapter(bridgeType2, localAdapter2, true);
        coordinator.setOutboundLocalBridgeAdapter(bridgeType2, localAdapter2);
        coordinator.setIsRemoteBridgeAdapter(bridgeType2, chainId, remoteAdapter, true);
        coordinator.setOutboundRemoteBridgeAdapter(bridgeType2, chainId, remoteAdapter);
        assertTrue(coordinator.supportsBridgeTypeFor(bridgeType2, chainId));

        // Rollback successfully via different bridge type
        vm.prank(relayer);
        bytes32 rollbackMsgId =
            coordinator.rollback(bridgeType2, chainId, messageData, messageId, "rollback bridge data", 1 ether);

        assertEq(coordinator.failedMessageExecutions(messageId), bytes32(0), "failed message execution not deleted");
        BridgeMessage memory expectedRollbackMessage = BridgeMessage({
            sender: bytes32(0),
            recipient: remoteUser,
            sourceWhitelabel: coordinator.encodeOmnichainAddress(address(gusd)),
            destinationWhitelabel: coordinator.encodeOmnichainAddress(address(gusd)),
            amount: 100e18
        });
        bytes memory expectedRollbackMessageData = coordinator.encodeBridgeMessage(expectedRollbackMessage);
        (
            uint256 chainId_,
            bytes32 remoteAdapter_,
            bytes memory rollbackMessageData,
            address refundAddress,
            bytes memory bridgeParams,
            bytes32 messageId_
        ) = localAdapter2.lastBridgeCall();
        assertEq(chainId_, chainId, "chain id mismatch");
        assertEq(remoteAdapter_, remoteAdapter, "remote adapter mismatch");
        assertEq(rollbackMessageData, expectedRollbackMessageData, "message mismatch");
        assertEq(refundAddress, relayer, "refund address mismatch");
        assertEq(bridgeParams, "rollback bridge data", "bridge params mismatch");
        assertEq(messageId_, rollbackMsgId, "rollback message id mismatch");
    }
}
