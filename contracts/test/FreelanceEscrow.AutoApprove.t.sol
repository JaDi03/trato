// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FreelanceEscrow} from "../FreelanceEscrow.sol";
import {FreelanceEscrowTestBase} from "./FreelanceEscrow.Base.t.sol";

/// @notice autoApprove timing and the client's review-window limits.
contract FreelanceEscrowAutoApproveTest is FreelanceEscrowTestBase {
    uint256 internal id;
    uint256 internal deliveredAt;

    function setUp() public override {
        super.setUp();
        id = _createN(TOTAL, 2); // 2 x 5_000_000, REVIEW = 3 days, 1 revision
        _toDelivered(id, 0);
        deliveredAt = block.timestamp;
    }

    function test_Revert_AutoApprove_BeforeReviewPeriodEnds() public {
        vm.warp(deliveredAt + REVIEW - 1);
        vm.prank(stranger);
        vm.expectRevert(FreelanceEscrow.TooEarly.selector);
        escrow.autoApprove(id, 0);
    }

    function test_Revert_AutoApprove_ImmediatelyAfterDelivery() public {
        vm.expectRevert(FreelanceEscrow.TooEarly.selector);
        escrow.autoApprove(id, 0);
    }

    function test_AutoApprove_AtExactlyPeriodEnd_AnyCaller() public {
        vm.warp(deliveredAt + REVIEW);
        vm.prank(stranger);
        escrow.autoApprove(id, 0);
        _assertState(id, 0, PAID);
        assertEq(_claim(p1), 3_500_000);
        assertEq(_claim(p2), 1_500_000);
        assertEq(_claim(client), 0);
        assertEq(escrow.getJob(id).paid, 5_000_000);
    }

    function test_AutoApprove_AfterPeriod_ByArbiterFreelancerAndClient() public {
        vm.warp(deliveredAt + REVIEW + 30 days);
        vm.prank(arbiter);
        escrow.autoApprove(id, 0);
        _assertState(id, 0, PAID);

        _toDelivered(id, 1);
        vm.warp(block.timestamp + REVIEW);
        vm.prank(freelancer);
        escrow.autoApprove(id, 1);
        assertTrue(escrow.getJob(id).completed);
    }

    function test_AutoApprove_EmitsAutomaticTrueThenPaid() public {
        vm.warp(deliveredAt + REVIEW);
        _e();
        emit FreelanceEscrow.MilestoneApproved(id, 0, true);
        _e();
        emit FreelanceEscrow.MilestonePaid(id, 0, 5_000_000, 0);
        vm.prank(stranger);
        escrow.autoApprove(id, 0);
    }

    function test_Revert_AutoApprove_AfterFinalRejection() public {
        _revise(id, 0);
        _deliver(id, 0);
        _reject(id, 0);
        vm.warp(block.timestamp + 365 days);
        vm.prank(stranger);
        vm.expectRevert(FreelanceEscrow.AlreadyRejected.selector);
        escrow.autoApprove(id, 0);
    }

    function test_Revert_AutoApprove_WrongState() public {
        vm.prank(stranger);
        vm.expectRevert(_badState(PENDING));
        escrow.autoApprove(id, 1);

        _approveM(id, 0);
        vm.warp(block.timestamp + REVIEW);
        vm.prank(stranger);
        vm.expectRevert(_badState(PAID));
        escrow.autoApprove(id, 0);
    }

    function test_Revert_AutoApprove_WhileInRevisionOrDisputed() public {
        _revise(id, 0);
        vm.warp(block.timestamp + 30 days);
        vm.prank(stranger);
        vm.expectRevert(_badState(IN_REVISION));
        escrow.autoApprove(id, 0);
    }

    // ------------------------------------------------------------ client limits at/after period end

    function test_Revert_ClientRequestRevision_AtAndAfterPeriodEnd() public {
        vm.warp(deliveredAt + REVIEW);
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.ReviewPeriodExpired.selector);
        escrow.requestRevision(id, 0);
        vm.warp(deliveredAt + REVIEW + 1 days);
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.ReviewPeriodExpired.selector);
        escrow.requestRevision(id, 0);
    }

    function test_Revert_ClientRejectDelivery_AtAndAfterPeriodEnd() public {
        uint256 id0 = _createNRev(TOTAL, 1, 0); // revisions exhausted from the start
        _toDelivered(id0, 0);
        uint256 at = block.timestamp;
        vm.warp(at + REVIEW - 1);
        // still within the window: allowed (checked via a snapshot so we can test the boundary next)
        uint256 snap = vm.snapshotState();
        _reject(id0, 0);
        assertTrue(_ms(id0, 0).rejectedFinal);
        vm.revertToState(snap);

        vm.warp(at + REVIEW);
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.ReviewPeriodExpired.selector);
        escrow.rejectDelivery(id0, 0);
        vm.warp(at + REVIEW + 5 days);
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.ReviewPeriodExpired.selector);
        escrow.rejectDelivery(id0, 0);
    }

    function test_Revert_ClientOpenDispute_AtAndAfterPeriodEnd() public {
        vm.warp(deliveredAt + REVIEW);
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.ReviewPeriodExpired.selector);
        escrow.openDispute(id, 0);
        vm.warp(deliveredAt + REVIEW + 10 days);
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.ReviewPeriodExpired.selector);
        escrow.openDispute(id, 0);
    }

    function test_ClientActions_StillWorkOneSecondBeforePeriodEnd() public {
        vm.warp(deliveredAt + REVIEW - 1);
        uint256 snap = vm.snapshotState();
        _revise(id, 0);
        _assertState(id, 0, IN_REVISION);
        vm.revertToState(snap);
        _clientDispute(id, 0);
        _assertState(id, 0, DISPUTED);
    }

    function test_ClientApprove_StillWorksAtAndAfterPeriodEnd() public {
        vm.warp(deliveredAt + REVIEW + 20 days);
        _approveM(id, 0);
        _assertState(id, 0, PAID);
        assertEq(_claim(p1), 3_500_000);
    }

    function test_ClientApprove_WorksAfterFinalRejection() public {
        _revise(id, 0);
        _deliver(id, 0);
        _reject(id, 0);
        vm.warp(block.timestamp + 10 days);
        _approveM(id, 0);
        _assertState(id, 0, PAID);
    }

    function test_ClientDispute_AllowedAfterFinalRejection_EvenPastReviewPeriod() public {
        _revise(id, 0);
        _deliver(id, 0);
        _reject(id, 0);
        vm.warp(block.timestamp + REVIEW + 1 days);
        _clientDispute(id, 0);
        _assertState(id, 0, DISPUTED);
    }
}
