// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FreelanceEscrow} from "../FreelanceEscrow.sol";
import {FreelanceEscrowTestBase} from "./FreelanceEscrow.Base.t.sol";

/// @notice State-machine unit tests: every legal transition and every illegal one.
contract FreelanceEscrowTest is FreelanceEscrowTestBase {
    uint256 internal id;

    function setUp() public override {
        super.setUp();
        id = _createN(TOTAL, 2); // two milestones of 5_000_000
    }

    // ------------------------------------------------------------ legal moves

    function test_HappyPath_PendingToPaid() public {
        _assertState(id, 0, PENDING);
        _start(id, 0);
        _assertState(id, 0, IN_PROGRESS);
        _deliver(id, 0);
        _assertState(id, 0, DELIVERED);

        _e();
        emit FreelanceEscrow.MilestoneApproved(id, 0, false);
        _e();
        emit FreelanceEscrow.MilestonePaid(id, 0, 5_000_000, 0);
        _approveM(id, 0);

        _assertState(id, 0, PAID);
        assertEq(_claim(p1), 3_500_000);
        assertEq(_claim(p2), 1_500_000);
        FreelanceEscrow.JobView memory j = escrow.getJob(id);
        assertEq(j.paid, 5_000_000);
        assertEq(j.remaining, 5_000_000);
        assertFalse(j.completed);
    }

    function test_RevisionLoop_DeliveredToInRevisionToDelivered() public {
        _toDelivered(id, 0);
        _revise(id, 0);
        _assertState(id, 0, IN_REVISION);
        assertEq(_ms(id, 0).revisionsUsed, 1);
        _deliver(id, 0);
        _assertState(id, 0, DELIVERED);
        _approveM(id, 0);
        _assertState(id, 0, PAID);
    }

    function test_DisputePath_DeliveredToDisputedToPaid() public {
        _toDelivered(id, 0);
        _clientDispute(id, 0);
        _assertState(id, 0, DISPUTED);
        _resolve(id, 0, 1_000_000);
        _assertState(id, 0, PAID);
    }

    function test_Refund_InProgressToRefunded() public {
        _start(id, 0);
        vm.warp(_ms(id, 0).deadline + 1);
        _refundM(id, 0);
        _assertState(id, 0, REFUNDED);
        assertEq(_claim(client), 5_000_000);
    }

    function test_Refund_PendingToRefunded() public {
        vm.warp(_ms(id, 0).unlockedAt + 14 days + 1);
        _refundM(id, 0);
        _assertState(id, 0, REFUNDED);
    }

    function test_Refund_FinalRejectionToRefunded() public {
        _toRejected(id, 0);
        vm.warp(block.timestamp + 7 days);
        vm.prank(client);
        escrow.refundAfterRejection(id, 0);
        _assertState(id, 0, REFUNDED);
        assertEq(_claim(client), 5_000_000);
    }

    function test_JobCompletes_OnlyWhenAllMilestonesTerminal() public {
        _toDelivered(id, 0);
        _approveM(id, 0);
        assertFalse(escrow.getJob(id).completed);
        _toDelivered(id, 1);
        _e();
        emit FreelanceEscrow.JobCompleted(id);
        _approveM(id, 1);
        assertTrue(escrow.getJob(id).completed);
    }

    // ------------------------------------------------------------ sequential gating

    function test_Start_Milestone1BlockedUntilMilestone0Terminal() public {
        vm.prank(freelancer);
        vm.expectRevert(FreelanceEscrow.MilestoneLocked.selector);
        escrow.startMilestone(id, 1);
        _start(id, 0);
        vm.prank(freelancer);
        vm.expectRevert(FreelanceEscrow.MilestoneLocked.selector);
        escrow.startMilestone(id, 1);
        _deliver(id, 0);
        vm.prank(freelancer);
        vm.expectRevert(FreelanceEscrow.MilestoneLocked.selector);
        escrow.startMilestone(id, 1);
    }

    function test_Start_Milestone1AfterMilestone0Paid() public {
        _toDelivered(id, 0);
        _approveM(id, 0);
        _start(id, 1);
        _assertState(id, 1, IN_PROGRESS);
    }

    function test_Start_Milestone1AfterMilestone0Refunded() public {
        _start(id, 0);
        vm.warp(_ms(id, 0).deadline + 1);
        _refundM(id, 0);
        _start(id, 1);
        _assertState(id, 1, IN_PROGRESS);
    }

    function test_Start_Milestone1WhileMilestone0Disputed() public {
        _toDisputed(id, 0);
        _start(id, 1);
        _assertState(id, 1, IN_PROGRESS);
        _assertState(id, 0, DISPUTED);
    }

    // ------------------------------------------------------------ illegal moves

    function test_Revert_Start_WrongCaller() public {
        address[4] memory bad = [client, arbiter, stranger, p1];
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(bad[i]);
            vm.expectRevert(FreelanceEscrow.Unauthorized.selector);
            escrow.startMilestone(id, 0);
        }
    }

    function test_Revert_Start_WrongState() public {
        _start(id, 0);
        vm.prank(freelancer);
        vm.expectRevert(_badState(IN_PROGRESS));
        escrow.startMilestone(id, 0);
    }

    function test_Revert_NotFound() public {
        vm.prank(freelancer);
        vm.expectRevert(abi.encodeWithSelector(FreelanceEscrow.JobNotFound.selector, 99));
        escrow.startMilestone(99, 0);
        vm.prank(freelancer);
        vm.expectRevert(abi.encodeWithSelector(FreelanceEscrow.MilestoneNotFound.selector, 2));
        escrow.startMilestone(id, 2);
        vm.expectRevert(abi.encodeWithSelector(FreelanceEscrow.JobNotFound.selector, 0));
        escrow.getJob(0);
    }

    function test_Revert_Deliver_WrongCallerAndState() public {
        _start(id, 0);
        address[3] memory bad = [client, arbiter, stranger];
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(bad[i]);
            vm.expectRevert(FreelanceEscrow.Unauthorized.selector);
            escrow.deliver(id, 0);
        }
        // Pending milestone
        vm.prank(freelancer);
        vm.expectRevert(_badState(PENDING));
        escrow.deliver(id, 1);
        // Already delivered
        _deliver(id, 0);
        vm.prank(freelancer);
        vm.expectRevert(_badState(DELIVERED));
        escrow.deliver(id, 0);
    }

    function test_Revert_Approve_WrongCallerAndState() public {
        _start(id, 0);
        vm.prank(client);
        vm.expectRevert(_badState(IN_PROGRESS));
        escrow.approve(id, 0);

        _deliver(id, 0);
        address[4] memory bad = [freelancer, arbiter, stranger, p1];
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(bad[i]);
            vm.expectRevert(FreelanceEscrow.Unauthorized.selector);
            escrow.approve(id, 0);
        }
        _approveM(id, 0);
        vm.prank(client);
        vm.expectRevert(_badState(PAID));
        escrow.approve(id, 0);
    }

    function test_Revert_RequestRevision() public {
        _start(id, 0);
        vm.prank(client);
        vm.expectRevert(_badState(IN_PROGRESS));
        escrow.requestRevision(id, 0);

        _deliver(id, 0);
        address[3] memory bad = [freelancer, arbiter, stranger];
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(bad[i]);
            vm.expectRevert(FreelanceEscrow.Unauthorized.selector);
            escrow.requestRevision(id, 0);
        }
        _revise(id, 0); // uses the only allowed revision
        vm.prank(client);
        vm.expectRevert(_badState(IN_REVISION));
        escrow.requestRevision(id, 0);
        _deliver(id, 0);
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.RevisionsExhausted.selector);
        escrow.requestRevision(id, 0);
    }

    function test_Revert_RejectDelivery_BeforeRevisionsExhausted() public {
        _toDelivered(id, 0);
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.RevisionsAvailable.selector);
        escrow.rejectDelivery(id, 0);
    }

    function test_Revert_RejectDelivery_CallerStateAndRepeat() public {
        _start(id, 0);
        vm.prank(client);
        vm.expectRevert(_badState(IN_PROGRESS));
        escrow.rejectDelivery(id, 0);

        _deliver(id, 0);
        _revise(id, 0);
        _deliver(id, 0);
        address[3] memory bad = [freelancer, arbiter, stranger];
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(bad[i]);
            vm.expectRevert(FreelanceEscrow.Unauthorized.selector);
            escrow.rejectDelivery(id, 0);
        }
        _reject(id, 0);
        assertTrue(_ms(id, 0).rejectedFinal);
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.AlreadyRejected.selector);
        escrow.rejectDelivery(id, 0);
        // a finally-rejected delivery can no longer be revised
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.RevisionsExhausted.selector);
        escrow.requestRevision(id, 0);
    }

    function test_RejectDelivery_ImmediatelyWhenZeroRevisionsAllowed() public {
        uint256 id0 = _createNRev(TOTAL, 1, 0);
        _toDelivered(id0, 0);
        _reject(id0, 0);
        assertTrue(_ms(id0, 0).rejectedFinal);
        assertEq(_ms(id0, 0).rejectedAt, block.timestamp);
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.RevisionsExhausted.selector);
        escrow.requestRevision(id0, 0);
    }

    function test_Revert_OpenDispute_CallerAndState() public {
        _start(id, 0);
        vm.prank(client);
        vm.expectRevert(_badState(IN_PROGRESS));
        escrow.openDispute(id, 0);

        _deliver(id, 0);
        address[4] memory bad = [arbiter, stranger, p1, freelancer]; // freelancer: not rejected yet
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(bad[i]);
            vm.expectRevert(FreelanceEscrow.Unauthorized.selector);
            escrow.openDispute(id, 0);
        }
        _clientDispute(id, 0);
        vm.prank(client);
        vm.expectRevert(_badState(DISPUTED));
        escrow.openDispute(id, 0);
    }

    function test_Revert_ResolveDispute_CallerAndState() public {
        _toDelivered(id, 0);
        vm.prank(arbiter);
        vm.expectRevert(_badState(DELIVERED));
        escrow.resolveDispute(id, 0, 0);

        _clientDispute(id, 0);
        address[4] memory bad = [client, freelancer, stranger, p1];
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(bad[i]);
            vm.expectRevert(FreelanceEscrow.Unauthorized.selector);
            escrow.resolveDispute(id, 0, 0);
        }
        _resolve(id, 0, 0);
        vm.prank(arbiter);
        vm.expectRevert(_badState(PAID));
        escrow.resolveDispute(id, 0, 0);
    }

    function test_Revert_RefundMilestone_CallerAndState() public {
        _start(id, 0);
        vm.warp(_ms(id, 0).deadline + 1);
        address[3] memory bad = [freelancer, arbiter, stranger];
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(bad[i]);
            vm.expectRevert(FreelanceEscrow.Unauthorized.selector);
            escrow.refundMilestone(id, 0);
        }
        _deliver(id, 0);
        vm.prank(client);
        vm.expectRevert(_badState(DELIVERED));
        escrow.refundMilestone(id, 0);
        _approveM(id, 0);
        vm.prank(client);
        vm.expectRevert(_badState(PAID));
        escrow.refundMilestone(id, 0);
    }

    function test_Revert_RefundMilestone_LockedPendingMilestone() public {
        vm.warp(T0 + 100 days);
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.MilestoneLocked.selector);
        escrow.refundMilestone(id, 1);
    }
}
