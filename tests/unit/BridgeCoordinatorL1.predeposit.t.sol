// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PredepositCoordinator, BridgeMessageCoordinator } from "../../src/coordinator/PredepositCoordinator.sol";
import { BridgeCoordinator } from "../../src/coordinator/BridgeCoordinator.sol";
import { IBridgeAdapter } from "../../src/interfaces/IBridgeAdapter.sol";

import { BridgeCoordinatorL1Harness } from "../harness/BridgeCoordinatorL1Harness.sol";

abstract contract BridgeCoordinatorL1_PredepositCoordinator_Test is Test {
    BridgeCoordinatorL1Harness coordinator;

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

    address manager = makeAddr("manager");
    bytes32 managerRole;
    bytes32 chainNickname = keccak256("pancake");

    function _resetInitializableStorageSlot() internal {
        // reset the Initializable storage slot to allow usage of deployed instance in tests
        vm.store(address(coordinator), coordinator.exposed_initializableStorageSlot(), bytes32(0));
    }

    function setUp() public virtual {
        coordinator = new BridgeCoordinatorL1Harness();
        _resetInitializableStorageSlot();
        coordinator.initialize(share, admin);

        managerRole = coordinator.PREDEPOSIT_MANAGER_ROLE();
        vm.prank(admin);
        coordinator.grantRole(managerRole, manager);

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

contract BridgeCoordinatorL1_PredepositCoordinator_Predeposit_Test is BridgeCoordinatorL1_PredepositCoordinator_Test {
    uint256 amount = 42 ether;

    function setUp() public override {
        super.setUp();
        coordinator.workaround_setPredepositState(chainNickname, PredepositCoordinator.PredepositState.ENABLED);
    }

    function testFuzz_shouldRevert_whenPredepositNotEnabled(uint8 state) public {
        state = state % 4;
        vm.assume(state != uint8(PredepositCoordinator.PredepositState.ENABLED));

        coordinator.workaround_setPredepositState(chainNickname, PredepositCoordinator.PredepositState(state));

        vm.expectRevert(PredepositCoordinator.Predeposit_NotEnabled.selector);
        vm.prank(sender);
        coordinator.predeposit(chainNickname, remoteRecipient, amount);
    }

    function test_shouldRevert_whenZeroRemoteRecipient() public {
        vm.expectRevert(PredepositCoordinator.Predeposit_ZeroRemoteRecipient.selector);
        vm.prank(sender);
        coordinator.predeposit(chainNickname, bytes32(0), amount);
    }

    function test_shouldRevert_whenZeroAmount() public {
        vm.expectRevert(PredepositCoordinator.Predeposit_ZeroAmount.selector);
        vm.prank(sender);
        coordinator.predeposit(chainNickname, remoteRecipient, 0);
    }

    function testFuzz_shouldPredeposit(uint256 _amount) public {
        vm.assume(_amount > 0);

        vm.expectEmit();
        emit PredepositCoordinator.Predeposited(chainNickname, sender, remoteRecipient, _amount);

        vm.expectCall(
            share, abi.encodeWithSelector(IERC20.transferFrom.selector, sender, address(coordinator), _amount)
        );

        vm.prank(sender);
        coordinator.predeposit(chainNickname, remoteRecipient, _amount);

        assertEq(coordinator.getPredeposit(chainNickname, sender, remoteRecipient), _amount);
        assertEq(coordinator.getTotalPredeposits(chainNickname), _amount);
    }

    function test_shouldAccumulatePredeposits() public {
        uint256 firstAmount = amount;
        uint256 secondAmount = amount * 2;

        vm.prank(sender);
        coordinator.predeposit(chainNickname, remoteRecipient, firstAmount);

        vm.prank(sender);
        coordinator.predeposit(chainNickname, remoteRecipient, secondAmount);

        assertEq(coordinator.getPredeposit(chainNickname, sender, remoteRecipient), firstAmount + secondAmount);
        assertEq(coordinator.getTotalPredeposits(chainNickname), firstAmount + secondAmount);
    }

    function test_shouldAccumulateTotalPredepositsMultipleUsers() public {
        address anotherSender = makeAddr("anotherSender");
        uint256 firstAmount = amount;
        uint256 secondAmount = amount * 2;

        vm.prank(sender);
        coordinator.predeposit(chainNickname, remoteRecipient, firstAmount);

        vm.prank(anotherSender);
        coordinator.predeposit(chainNickname, remoteRecipient, secondAmount);

        assertEq(coordinator.getPredeposit(chainNickname, sender, remoteRecipient), firstAmount);
        assertEq(coordinator.getPredeposit(chainNickname, anotherSender, remoteRecipient), secondAmount);
        assertEq(coordinator.getTotalPredeposits(chainNickname), firstAmount + secondAmount);
    }
}

contract BridgeCoordinatorL1_PredepositCoordinator_BridgePredeposit_Test is
    BridgeCoordinatorL1_PredepositCoordinator_Test
{
    bytes bridgeParams = "bridge params";

    function setUp() public override {
        super.setUp();
        coordinator.workaround_setPredepositState(chainNickname, PredepositCoordinator.PredepositState.DISPATCHED);
        coordinator.workaround_setPredepositChainId(chainNickname, remoteChainId);
        coordinator.workaround_setPredeposit(chainNickname, sender, remoteRecipient, 100 ether);
        coordinator.workaround_setTotalPredeposits(chainNickname, 200 ether);
    }

    function testFuzz_shouldRevert_whenPredepositNotDispatched(uint8 state) public {
        state = state % 4;
        vm.assume(state != uint8(PredepositCoordinator.PredepositState.DISPATCHED));

        coordinator.workaround_setPredepositState(chainNickname, PredepositCoordinator.PredepositState(state));

        vm.expectRevert(PredepositCoordinator.Predeposit_DispatchNotEnabled.selector);
        coordinator.bridgePredeposit(bridgeType, chainNickname, sender, remoteRecipient, bridgeParams);
    }

    function test_shouldRevert_whenNotAssignedChainId() public {
        coordinator.workaround_setPredepositChainId(chainNickname, 0);

        vm.expectRevert(PredepositCoordinator.Predeposit_ChainIdZero.selector);
        coordinator.bridgePredeposit(bridgeType, chainNickname, sender, remoteRecipient, bridgeParams);
    }

    function test_shouldRevert_whenNoAmountToBridge() public {
        coordinator.workaround_setPredeposit(chainNickname, sender, remoteRecipient, 0);

        vm.expectRevert(PredepositCoordinator.Predeposit_ZeroAmount.selector);
        coordinator.bridgePredeposit(bridgeType, chainNickname, sender, remoteRecipient, bridgeParams);
    }

    function test_shouldRevert_whenChainAdaptersNotSet() public {
        vm.expectRevert(BridgeCoordinator.NoLocalBridgeAdapter.selector);
        coordinator.bridgePredeposit(bridgeType + 1, chainNickname, sender, remoteRecipient, bridgeParams);
    }

    function testFuzz_shouldDispatchPredeposit(uint256 fee, uint256 amount) public {
        uint256 totalPredeposits = type(uint256).max;
        amount = bound(amount, 1, totalPredeposits);
        fee = bound(fee, 0, 1 ether);
        coordinator.workaround_setPredeposit(chainNickname, sender, remoteRecipient, amount);
        coordinator.workaround_setTotalPredeposits(chainNickname, totalPredeposits);

        address caller = makeAddr("caller");
        deal(caller, fee);

        bytes memory expectedBridgeMessageData =
            coordinator.encodeBridgeMessage(coordinator.encodeOmnichainAddress(sender), remoteRecipient, amount);

        vm.expectEmit();
        emit BridgeMessageCoordinator.BridgedOut(sender, remoteRecipient, amount, messageId);
        vm.expectEmit();
        emit PredepositCoordinator.PredepositBridgedOut(chainNickname, messageId);

        vm.expectCall(
            localAdapter,
            fee,
            abi.encodeWithSelector(
                IBridgeAdapter.bridge.selector,
                remoteChainId,
                remoteAdapter,
                expectedBridgeMessageData,
                caller, // caller as refund address
                bridgeParams
            )
        );

        vm.prank(caller);
        coordinator.bridgePredeposit{ value: fee }(bridgeType, chainNickname, sender, remoteRecipient, bridgeParams);

        assertEq(coordinator.getPredeposit(chainNickname, sender, remoteRecipient), 0);
        assertEq(coordinator.getTotalPredeposits(chainNickname), totalPredeposits - amount);
    }
}

contract BridgeCoordinatorL1_PredepositCoordinator_WithdrawPredeposit_Test is
    BridgeCoordinatorL1_PredepositCoordinator_Test
{
    function setUp() public override {
        super.setUp();
        coordinator.workaround_setPredepositState(chainNickname, PredepositCoordinator.PredepositState.WITHDRAWN);
        coordinator.workaround_setPredeposit(chainNickname, sender, remoteRecipient, 100 ether);
        coordinator.workaround_setTotalPredeposits(chainNickname, 200 ether);
    }

    function testFuzz_shouldRevert_whenPredepositNotWithdrawn(uint8 state) public {
        state = state % 4;
        vm.assume(state != uint8(PredepositCoordinator.PredepositState.WITHDRAWN));

        coordinator.workaround_setPredepositState(chainNickname, PredepositCoordinator.PredepositState(state));

        vm.expectRevert(PredepositCoordinator.Predeposit_WithdrawalsNotEnabled.selector);
        vm.prank(sender);
        coordinator.withdrawPredeposit(chainNickname, remoteRecipient, recipient);
    }

    function test_shouldRevert_whenZeroAmountToWithdraw() public {
        coordinator.workaround_setPredeposit(chainNickname, sender, remoteRecipient, 0);

        vm.expectRevert(PredepositCoordinator.Predeposit_ZeroAmount.selector);
        vm.prank(sender);
        coordinator.withdrawPredeposit(chainNickname, remoteRecipient, recipient);
    }

    function test_shouldRevert_whenZeroRecipient() public {
        vm.expectRevert(PredepositCoordinator.Predeposit_ZeroRecipient.selector);
        vm.prank(sender);
        coordinator.withdrawPredeposit(chainNickname, remoteRecipient, address(0));
    }

    function testFuzz_shouldWithdrawPredeposit(uint256 amount) public {
        uint256 totalPredeposits = type(uint256).max;
        amount = bound(amount, 1, totalPredeposits);
        coordinator.workaround_setPredeposit(chainNickname, sender, remoteRecipient, amount);
        coordinator.workaround_setTotalPredeposits(chainNickname, totalPredeposits);

        vm.expectEmit();
        emit PredepositCoordinator.PredepositWithdrawn(chainNickname, sender, remoteRecipient, recipient, amount);

        vm.expectCall(share, abi.encodeWithSelector(IERC20.transfer.selector, recipient, amount));

        vm.prank(sender);
        coordinator.withdrawPredeposit(chainNickname, remoteRecipient, recipient);

        assertEq(coordinator.getPredeposit(chainNickname, sender, remoteRecipient), 0);
        assertEq(coordinator.getTotalPredeposits(chainNickname), totalPredeposits - amount);
    }
}

contract BridgeCoordinatorL1_PredepositCoordinator_EnablePredeposits_Test is
    BridgeCoordinatorL1_PredepositCoordinator_Test
{
    function test_shouldRevert_whenCallerNotManagerRole() public {
        address caller = makeAddr("notManager");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        coordinator.enablePredeposits(chainNickname);
    }

    function testFuzz_shouldRevert_whenChainInIncorrectState(uint8 state) public {
        state = state % 4;
        vm.assume(state != uint8(PredepositCoordinator.PredepositState.DISABLED));

        coordinator.workaround_setPredepositState(chainNickname, PredepositCoordinator.PredepositState(state));

        vm.expectRevert(PredepositCoordinator.Predeposit_InvalidStateTransition.selector);
        vm.prank(manager);
        coordinator.enablePredeposits(chainNickname);
    }

    function test_shouldEnablePredeposits() public {
        vm.expectEmit();
        emit PredepositCoordinator.PredepositStateChanged(chainNickname, PredepositCoordinator.PredepositState.ENABLED);

        vm.prank(manager);
        coordinator.enablePredeposits(chainNickname);

        PredepositCoordinator.PredepositState state = coordinator.getChainPredepositState(chainNickname);
        assertEq(uint8(state), uint8(PredepositCoordinator.PredepositState.ENABLED));
    }
}

contract BridgeCoordinatorL1_PredepositCoordinator_EnablePredepositsDispatch_Test is
    BridgeCoordinatorL1_PredepositCoordinator_Test
{
    function setUp() public override {
        super.setUp();
        coordinator.workaround_setPredepositState(chainNickname, PredepositCoordinator.PredepositState.ENABLED);
    }

    function test_shouldRevert_whenCallerNotManagerRole() public {
        address caller = makeAddr("notManager");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        coordinator.enablePredepositsDispatch(chainNickname, remoteChainId);
    }

    function testFuzz_shouldRevert_whenChainInIncorrectState(uint8 state) public {
        state = state % 4;
        vm.assume(state != uint8(PredepositCoordinator.PredepositState.ENABLED));

        coordinator.workaround_setPredepositState(chainNickname, PredepositCoordinator.PredepositState(state));

        vm.expectRevert(PredepositCoordinator.Predeposit_InvalidStateTransition.selector);
        vm.prank(manager);
        coordinator.enablePredepositsDispatch(chainNickname, remoteChainId);
    }

    function test_shouldRevert_whenChainIdIsZero() public {
        vm.expectRevert(PredepositCoordinator.Predeposit_ChainIdZero.selector);
        vm.prank(manager);
        coordinator.enablePredepositsDispatch(chainNickname, 0);
    }

    function test_shouldRevert_whenChainIdAlreadyAssigned() public {
        coordinator.workaround_setPredepositChainId(chainNickname, 1);

        vm.expectRevert(PredepositCoordinator.Predeposit_ChainIdAlreadySet.selector);
        vm.prank(manager);
        coordinator.enablePredepositsDispatch(chainNickname, remoteChainId);
    }

    function testFuzz_shouldEnablePredepositsDispatch(uint256 chainId) public {
        vm.assume(chainId != 0);

        vm.expectEmit();
        emit PredepositCoordinator.PredepositStateChanged(
            chainNickname, PredepositCoordinator.PredepositState.DISPATCHED
        );

        vm.expectEmit();
        emit PredepositCoordinator.ChainIdAssignedToNickname(chainNickname, chainId);

        vm.prank(manager);
        coordinator.enablePredepositsDispatch(chainNickname, chainId);

        PredepositCoordinator.PredepositState state = coordinator.getChainPredepositState(chainNickname);
        assertEq(uint8(state), uint8(PredepositCoordinator.PredepositState.DISPATCHED));
        assertEq(coordinator.getChainIdForNickname(chainNickname), chainId);
    }
}

contract BridgeCoordinatorL1_PredepositCoordinator_EnablePredepositsWithdraw_Test is
    BridgeCoordinatorL1_PredepositCoordinator_Test
{
    function setUp() public override {
        super.setUp();
        coordinator.workaround_setPredepositState(chainNickname, PredepositCoordinator.PredepositState.ENABLED);
    }

    function test_shouldRevert_whenCallerNotManagerRole() public {
        address caller = makeAddr("notManager");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        coordinator.enablePredepositsWithdraw(chainNickname);
    }

    function testFuzz_shouldRevert_whenChainInIncorrectState(uint8 state) public {
        state = state % 4;
        vm.assume(state != uint8(PredepositCoordinator.PredepositState.ENABLED));

        coordinator.workaround_setPredepositState(chainNickname, PredepositCoordinator.PredepositState(state));

        vm.expectRevert(PredepositCoordinator.Predeposit_InvalidStateTransition.selector);
        vm.prank(manager);
        coordinator.enablePredepositsWithdraw(chainNickname);
    }

    function test_shouldEnablePredepositsWithdraw() public {
        vm.expectEmit();
        emit PredepositCoordinator.PredepositStateChanged(
            chainNickname, PredepositCoordinator.PredepositState.WITHDRAWN
        );

        vm.prank(manager);
        coordinator.enablePredepositsWithdraw(chainNickname);

        PredepositCoordinator.PredepositState state = coordinator.getChainPredepositState(chainNickname);
        assertEq(uint8(state), uint8(PredepositCoordinator.PredepositState.WITHDRAWN));
    }
}

contract BridgeCoordinatorL1_PredepositCoordinator_SetChainIdToNickname_Test is
    BridgeCoordinatorL1_PredepositCoordinator_Test
{
    function setUp() public override {
        super.setUp();
        coordinator.workaround_setPredepositState(chainNickname, PredepositCoordinator.PredepositState.DISPATCHED);
        coordinator.workaround_setPredepositChainId(chainNickname, remoteChainId + 10);
    }

    function test_shouldRevert_whenCallerNotManagerRole() public {
        address caller = makeAddr("notManager");

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, managerRole)
        );
        vm.prank(caller);
        coordinator.setChainIdToNickname(chainNickname, remoteChainId);
    }

    function testFuzz_shouldRevert_whenChainInIncorrectState(uint8 state) public {
        state = state % 4;
        vm.assume(state != uint8(PredepositCoordinator.PredepositState.DISPATCHED));

        coordinator.workaround_setPredepositState(chainNickname, PredepositCoordinator.PredepositState(state));

        vm.expectRevert(PredepositCoordinator.Predeposit_DispatchNotEnabled.selector);
        vm.prank(manager);
        coordinator.setChainIdToNickname(chainNickname, remoteChainId);
    }

    function test_shouldRevert_whenChainIdIsZero() public {
        vm.expectRevert(PredepositCoordinator.Predeposit_ChainIdZero.selector);
        vm.prank(manager);
        coordinator.setChainIdToNickname(chainNickname, 0);
    }

    function testFuzz_shouldSetChainIdToNickname(uint256 chainId) public {
        vm.assume(chainId != 0);

        vm.expectEmit();
        emit PredepositCoordinator.ChainIdAssignedToNickname(chainNickname, chainId);

        vm.prank(manager);
        coordinator.setChainIdToNickname(chainNickname, chainId);

        assertEq(coordinator.getChainIdForNickname(chainNickname), chainId);
    }
}
