// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import { BridgeCoordinator, IBridgeAdapter, IERC20 } from "../../src/coordinator/BridgeCoordinator.sol";

import { BridgeCoordinatorHarness } from "../harness/BridgeCoordinatorHarness.sol";

abstract contract BridgeCoordinatorTest is Test {
    BridgeCoordinatorHarness coordinator;

    address share = makeAddr("share");
    address admin = makeAddr("admin");
    address sender = makeAddr("sender");
    bytes32 remoteSender = bytes32(uint256(uint160(makeAddr("remoteSender"))));
    address recipient = makeAddr("recipient");
    bytes32 remoteRecipient = bytes32(uint256(uint160(makeAddr("remoteRecipient"))));
    bytes32 messageId = keccak256("messageId");

    uint16 bridgeType = 7;
    uint256 remoteChainId = 42;
    address localAdapter = makeAddr("localAdapter");
    bytes32 remoteAdapter = bytes32(uint256(uint160(makeAddr("remoteAdapter"))));

    function _resetInitializableStorageSlot() internal {
        // reset the Initializable storage slot to allow usage of deployed instance in tests
        vm.store(address(coordinator), coordinator.exposed_initializableStorageSlot(), bytes32(0));
    }

    function setUp() public virtual {
        coordinator = new BridgeCoordinatorHarness();
        _resetInitializableStorageSlot();
        coordinator.initialize(share, admin);

        vm.mockCall(
            localAdapter,
            abi.encodeWithSelector(IBridgeAdapter.bridgeCoordinator.selector),
            abi.encode(address(coordinator))
        );
        vm.mockCall(localAdapter, abi.encodeWithSelector(IBridgeAdapter.bridgeType.selector), abi.encode(bridgeType));
        vm.mockCall(localAdapter, abi.encodeWithSelector(IBridgeAdapter.estimateBridgeFee.selector), abi.encode(0));
        vm.mockCall(localAdapter, abi.encodeWithSelector(IBridgeAdapter.bridge.selector), abi.encode(messageId));

        vm.mockCall(share, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        vm.mockCall(share, abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));

        coordinator.workaround_setOutboundLocalBridgeAdapter(bridgeType, localAdapter);
        coordinator.workaround_setOutboundRemoteBridgeAdapter(bridgeType, remoteChainId, remoteAdapter);
    }
}

contract BridgeCoordinator_Constructor_Test is BridgeCoordinatorTest {
    function test_shouldDisableInitializers() public {
        coordinator = new BridgeCoordinatorHarness();
        bytes32 initializableSlotValue = vm.load(address(coordinator), coordinator.exposed_initializableStorageSlot());
        assertEq(uint64(uint256(initializableSlotValue)), type(uint64).max);
    }
}

contract BridgeCoordinator_Initialize_Test is BridgeCoordinatorTest {
    function setUp() public override {
        coordinator = new BridgeCoordinatorHarness();
        _resetInitializableStorageSlot();
    }

    function testFuzz_shouldSetShareTokenAndAdmin(address _share, address _admin) public {
        vm.assume(_share != address(0));
        vm.assume(_admin != address(0));

        coordinator.initialize(_share, _admin);

        assertEq(coordinator.shareToken(), _share);
        assertTrue(coordinator.hasRole(coordinator.DEFAULT_ADMIN_ROLE(), _admin));
    }

    function test_shouldRevertIfZeroShareToken() public {
        vm.expectRevert(BridgeCoordinator.ZeroShareToken.selector);
        coordinator.initialize(address(0), admin);
    }

    function test_shouldRevertIfZeroAdmin() public {
        vm.expectRevert(BridgeCoordinator.ZeroAdmin.selector);
        coordinator.initialize(share, address(0));
    }

    function test_shouldRevertIfAlreadyInitialized() public {
        coordinator.initialize(share, admin);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        coordinator.initialize(share, admin);
    }
}

abstract contract BridgeCoordinator_SettleInboundBridge_Test is BridgeCoordinatorTest {
    bytes messageData;

    function test_shouldRevert_whenCallerNotLocalAdapter_whenCallerNotInboundAdapter() public {
        address badCaller = makeAddr("badCaller");
        coordinator.workaround_setIsInboundOnlyLocalBridgeAdapter(bridgeType, badCaller, false);

        vm.expectRevert(BridgeCoordinator.OnlyLocalAdapter.selector);
        vm.prank(badCaller);
        coordinator.settleInboundMessage(bridgeType, remoteChainId, remoteAdapter, messageData, messageId);
    }

    function test_shouldRevert_whenRemoteSenderNotRemoteAdapter_whenRemoteSenderNotInboundAdapter() public {
        bytes32 badRemoteAdapter = bytes32(uint256(uint160(makeAddr("badRemoteAdapter"))));
        coordinator.workaround_setIsInboundOnlyRemoteBridgeAdapter(bridgeType, remoteChainId, badRemoteAdapter, false);

        vm.expectRevert(BridgeCoordinator.OnlyRemoteAdapter.selector);
        vm.prank(localAdapter);
        coordinator.settleInboundMessage(bridgeType, remoteChainId, badRemoteAdapter, messageData, messageId);
    }

    function test_shouldPass_whenCallerIsInboundOnlyLocalAdapter() public {
        address inboundOnlyLocalAdapter = makeAddr("inboundOnlyLocalAdapter");
        coordinator.workaround_setIsInboundOnlyLocalBridgeAdapter(bridgeType, inboundOnlyLocalAdapter, true);

        vm.prank(inboundOnlyLocalAdapter);
        coordinator.settleInboundMessage(bridgeType, remoteChainId, remoteAdapter, messageData, messageId);
    }

    function test_shouldPass_whenRemoteSenderIsInboundOnlyRemoteAdapter() public {
        bytes32 inboundOnlyRemoteAdapter = bytes32(uint256(uint160(makeAddr("inboundOnlyRemoteAdapter"))));
        coordinator.workaround_setIsInboundOnlyRemoteBridgeAdapter(
            bridgeType, remoteChainId, inboundOnlyRemoteAdapter, true
        );

        vm.prank(localAdapter);
        coordinator.settleInboundMessage(bridgeType, remoteChainId, inboundOnlyRemoteAdapter, messageData, messageId);
    }

    function test_shouldEmit_MessageIn() public {
        vm.expectEmit();
        emit BridgeCoordinator.MessageIn(bridgeType, remoteChainId, messageId, messageData);

        vm.prank(localAdapter);
        coordinator.settleInboundMessage(bridgeType, remoteChainId, remoteAdapter, messageData, messageId);
    }

    function test_shouldStoreFailedMessage_whenUnsupportedMessageType() public {
        // messageType 99 is unsupported
        messageData = abi.encode(uint8(99), bytes("some message data"));

        vm.expectEmit();
        emit BridgeCoordinator.MessageExecutionFailed(messageId);

        vm.prank(localAdapter);
        coordinator.settleInboundMessage(bridgeType, remoteChainId, remoteAdapter, messageData, messageId);

        bytes32 failedMessageHash = keccak256(abi.encode(remoteChainId, messageData));
        assertEq(coordinator.failedMessageExecutions(messageId), failedMessageHash);
    }
}

contract BridgeCoordinator_SupportsBridgeTypeFor_Test is BridgeCoordinatorTest {
    function test_shouldReturnTrue_whenLocalAndRemoteAdaptersSet() public view {
        assertTrue(coordinator.supportsBridgeTypeFor(bridgeType, remoteChainId));
    }

    function test_shouldReturnFalse_whenLocalAdapterNotSet() public view {
        assertFalse(coordinator.supportsBridgeTypeFor(bridgeType + 1, remoteChainId));
    }

    function test_shouldReturnFalse_whenRemoteAdapterNotSet() public view {
        assertFalse(coordinator.supportsBridgeTypeFor(bridgeType, remoteChainId + 1));
    }
}

contract BridgeCoordinator_EncodeDecodeOmnichainAddress_Test is BridgeCoordinatorTest {
    function testFuzz_shouldReturnEncodedAddress(address addr) public view {
        bytes32 oAddr = coordinator.encodeOmnichainAddress(addr);

        assertEq(oAddr, bytes32(uint256(uint160(addr))));
    }

    function testFuzz_shouldReturnDecodedAddress(bytes32 oAddr) public view {
        address addr = coordinator.decodeOmnichainAddress(oAddr);

        assertEq(addr, address(uint160(uint256(oAddr))));
    }

    function testFuzz_shouldReturnSameAddress_whenEncodeThenDecode(address addr) public view {
        bytes32 oAddr = coordinator.encodeOmnichainAddress(addr);
        address decodedAddr = coordinator.decodeOmnichainAddress(oAddr);

        assertEq(decodedAddr, addr);
    }
}
