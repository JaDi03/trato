// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FreelanceEscrow} from "../FreelanceEscrow.sol";
import {FreelanceEscrowTestBase} from "./FreelanceEscrow.Base.t.sol";

/// @notice Dispute opening, arbiter resolution, and timeout resolution.
contract FreelanceEscrowDisputeTest is FreelanceEscrowTestBase {
    uint256 internal id;
    uint256 internal constant AMOUNT = 5_000_000;

    function setUp() public override {
        super.setUp();
        id = _createN(TOTAL, 2); // 2 x 5_000_000; payees p1 70% / p2 30%
        _toDisputed(id, 0);
    }

    // ------------------------------------------------------------ arbiter resolution

    function test_Resolve_RefundZero_AllToPayees() public {
        _resolve(id, 0, 0);
        _assertState(id, 0, PAID);
        assertEq(_claim(client), 0);
        assertEq(_claim(p1), 3_500_000);
        assertEq(_claim(p2), 1_500_000);
        FreelanceEscrow.JobView memory j = escrow.getJob(id);
        assertEq(j.paid, AMOUNT);
        assertEq(j.refunded, 0);
    }

    function test_Resolve_PartialRefund() public {
        _resolve(id, 0, 1_234_567);
        assertEq(_claim(client), 1_234_567);
        uint256 payeeAmt = AMOUNT - 1_234_567; // 3_765_433
        assertEq(_claim(p1), (payeeAmt * 7000) / 10_000);
        assertEq(_claim(p2), payeeAmt - (payeeAmt * 7000) / 10_000);
        assertEq(_claim(p1) + _claim(p2) + _claim(client), AMOUNT);
        FreelanceEscrow.JobView memory j = escrow.getJob(id);
        assertEq(j.paid, payeeAmt);
        assertEq(j.refunded, 1_234_567);
        assertEq(j.remaining, TOTAL - AMOUNT);
    }

    function test_Resolve_FullRefund() public {
        _resolve(id, 0, AMOUNT);
        _assertState(id, 0, PAID);
        assertEq(_claim(client), AMOUNT);
        assertEq(_claim(p1), 0);
        assertEq(_claim(p2), 0);
        assertEq(escrow.getJob(id).paid, 0);
    }

    function test_Revert_Resolve_RefundAboveAmount() public {
        vm.prank(arbiter);
        vm.expectRevert(FreelanceEscrow.InvalidRefund.selector);
        escrow.resolveDispute(id, 0, AMOUNT + 1);
        _assertState(id, 0, DISPUTED);
    }

    function test_Revert_Resolve_OnlyArbiter() public {
        address[4] memory bad = [client, freelancer, p1, stranger];
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(bad[i]);
            vm.expectRevert(FreelanceEscrow.Unauthorized.selector);
            escrow.resolveDispute(id, 0, 0);
        }
    }

    function test_Resolve_RoundingExactWithOddAmounts() public {
        uint256 id2 = _createN(1_000_003, 3); // 333_300 / 333_300 / 333_403
        for (uint256 m; m < 2; ++m) {
            _toDelivered(id2, m);
            _approveM(id2, m);
        }
        uint256 p1Before = _claim(p1);
        uint256 p2Before = _claim(p2);
        _toDisputed(id2, 2);
        uint256 amount = _ms(id2, 2).amount;
        assertEq(amount, 333_403);
        _resolve(id2, 2, 111_111);
        uint256 payeeAmt = amount - 111_111;
        (, uint16[] memory sh) = escrow.getPayees(id2, 2);
        uint256[] memory exp = _split(payeeAmt, sh);
        assertEq(_claim(client), 111_111);
        assertEq(_claim(p1) - p1Before, exp[0]);
        assertEq(_claim(p2) - p2Before, exp[1]);
        assertEq(_claim(p1) + _claim(p2) - p1Before - p2Before + _claim(client), amount);
    }

    function test_Resolve_DoesNotAffectOtherMilestones() public {
        _resolve(id, 0, 1_000_000);
        _assertState(id, 1, PENDING);
        assertEq(_ms(id, 1).amount, AMOUNT);
        assertEq(escrow.getJob(id).remaining, AMOUNT);
        _start(id, 1);
        _toDelivered2();
    }

    function _toDelivered2() internal {
        _deliver(id, 1);
        _approveM(id, 1);
        _assertState(id, 1, PAID);
        assertTrue(escrow.getJob(id).completed);
    }

    function test_NextMilestoneCanStart_WhileOneDisputed() public {
        _assertState(id, 0, DISPUTED);
        assertEq(_ms(id, 1).unlockedAt, block.timestamp);
        _start(id, 1);
        _assertState(id, 1, IN_PROGRESS);
        _assertState(id, 0, DISPUTED);
        // job is not complete while a dispute is open
        _deliver(id, 1);
        _approveM(id, 1);
        assertFalse(escrow.getJob(id).completed);
        _resolve(id, 0, 0);
        assertTrue(escrow.getJob(id).completed);
    }

    // ------------------------------------------------------------ timeout

    function test_Revert_Timeout_BeforeThirtyDays() public {
        uint256 at = _ms(id, 0).disputedAt;
        vm.warp(at + 30 days - 1);
        vm.prank(stranger);
        vm.expectRevert(FreelanceEscrow.TooEarly.selector);
        escrow.resolveDisputeByTimeout(id, 0);
    }

    function test_Timeout_SplitsFiftyFifty_AnyCaller() public {
        uint256 at = _ms(id, 0).disputedAt;
        vm.warp(at + 30 days);
        vm.prank(stranger);
        escrow.resolveDisputeByTimeout(id, 0);
        _assertState(id, 0, PAID);
        assertEq(_claim(client), 2_500_000);
        assertEq(_claim(p1), 1_750_000);
        assertEq(_claim(p2), 750_000);
    }

    function test_Timeout_OddUnitGoesToPayees() public {
        uint256 id2 = _createN(10_000_001, 1);
        _toDisputed(id2, 0);
        vm.warp(block.timestamp + 30 days + 1 days);
        vm.prank(freelancer);
        escrow.resolveDisputeByTimeout(id2, 0);
        assertEq(_claim(client), 5_000_000);
        assertEq(_claim(p1) + _claim(p2), 5_000_001);
        assertEq(escrow.getJob(id2).paid, 5_000_001);
        assertEq(escrow.getJob(id2).refunded, 5_000_000);
    }

    function test_Revert_Timeout_WrongStateAndRepeat() public {
        vm.prank(stranger);
        vm.expectRevert(_badState(PENDING));
        escrow.resolveDisputeByTimeout(id, 1);

        vm.warp(block.timestamp + 30 days);
        escrow.resolveDisputeByTimeout(id, 0);
        vm.expectRevert(_badState(PAID));
        escrow.resolveDisputeByTimeout(id, 0);
    }

    function test_ArbiterCanStillResolve_AfterTimeoutWindow() public {
        vm.warp(block.timestamp + 90 days);
        _resolve(id, 0, 42);
        assertEq(_claim(client), 42);
    }

    // ------------------------------------------------------------ who may open

    function test_FreelancerDispute_OnlyAfterFinalRejection() public {
        _start(id, 1);
        _deliver(id, 1);
        vm.prank(freelancer);
        vm.expectRevert(FreelanceEscrow.Unauthorized.selector);
        escrow.openDispute(id, 1);

        _revise(id, 1);
        _deliver(id, 1);
        vm.prank(freelancer);
        vm.expectRevert(FreelanceEscrow.Unauthorized.selector);
        escrow.openDispute(id, 1);

        _reject(id, 1);
        vm.prank(freelancer);
        escrow.openDispute(id, 1);
        _assertState(id, 1, DISPUTED);
        assertEq(_ms(id, 1).disputedAt, block.timestamp);
    }

    function test_Dispute_ClientCanOpenOnLastMilestone_NoNextToUnlock() public {
        uint256 id2 = _createN(TOTAL, 1);
        _toDisputed(id2, 0);
        _assertState(id2, 0, DISPUTED);
    }
}
