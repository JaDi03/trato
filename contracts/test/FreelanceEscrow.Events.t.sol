// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FreelanceEscrow} from "../FreelanceEscrow.sol";
import {FreelanceEscrowTestBase} from "./FreelanceEscrow.Base.t.sol";

/// @notice Every state-changing function emits its event(s) with the right args.
contract FreelanceEscrowEventsTest is FreelanceEscrowTestBase {
    uint256 internal id;

    function setUp() public override {
        super.setUp();
        id = _createN(TOTAL, 2); // 2 x 5_000_000
    }

    function test_Event_JobCreated_And_FirstMilestoneUnlocked() public {
        FreelanceEscrow.MilestoneInput[] memory ms = _evenInputs(3, REVISIONS);
        vm.startPrank(client);
        usdc.approve(address(escrow), TOTAL);
        _e();
        emit FreelanceEscrow.JobCreated(2, client, freelancer, arbiter, TOTAL, 3, block.timestamp);
        _e();
        emit FreelanceEscrow.MilestoneUnlocked(2, 0, block.timestamp);
        uint256 newId = escrow.createJob(freelancer, arbiter, TOTAL, ms);
        vm.stopPrank();
        assertEq(newId, 2);
        assertEq(escrow.jobCount(), 2);
        assertEq(usdc.balanceOf(address(escrow)), 2 * TOTAL);
    }

    function test_Event_MilestoneStarted() public {
        _e();
        emit FreelanceEscrow.MilestoneStarted(id, 0, block.timestamp, block.timestamp + DELIVERY);
        _start(id, 0);
    }

    function test_Event_MilestoneDelivered() public {
        _start(id, 0);
        _e();
        emit FreelanceEscrow.MilestoneDelivered(id, 0, block.timestamp);
        _deliver(id, 0);
    }

    function test_Event_RevisionRequested() public {
        _toDelivered(id, 0);
        _e();
        emit FreelanceEscrow.RevisionRequested(id, 0, 1, block.timestamp + DELIVERY);
        _revise(id, 0);
    }

    function test_Event_DeliveryRejected() public {
        _toDelivered(id, 0);
        _revise(id, 0);
        _deliver(id, 0);
        _e();
        emit FreelanceEscrow.DeliveryRejected(id, 0, block.timestamp);
        _reject(id, 0);
    }

    function test_Event_Approve_Credits_Paid_Unlocked() public {
        _toDelivered(id, 0);
        _e();
        emit FreelanceEscrow.MilestoneApproved(id, 0, false);
        _e();
        emit FreelanceEscrow.Credited(p1, 3_500_000, id);
        _e();
        emit FreelanceEscrow.Credited(p2, 1_500_000, id);
        _e();
        emit FreelanceEscrow.MilestonePaid(id, 0, 5_000_000, 0);
        _e();
        emit FreelanceEscrow.MilestoneUnlocked(id, 1, block.timestamp);
        _approveM(id, 0);
    }

    function test_Event_AutoApprove_AutomaticTrue() public {
        _toDelivered(id, 0);
        vm.warp(block.timestamp + REVIEW);
        _e();
        emit FreelanceEscrow.MilestoneApproved(id, 0, true);
        vm.prank(stranger);
        escrow.autoApprove(id, 0);
    }

    function test_Event_DisputeOpened_ByClient_UnlocksNext() public {
        _toDelivered(id, 0);
        _e();
        emit FreelanceEscrow.DisputeOpened(id, 0, client);
        _e();
        emit FreelanceEscrow.MilestoneUnlocked(id, 1, block.timestamp);
        _clientDispute(id, 0);
    }

    function test_Event_DisputeOpened_ByFreelancerAfterRejection() public {
        _toRejected(id, 0);
        _e();
        emit FreelanceEscrow.DisputeOpened(id, 0, freelancer);
        vm.prank(freelancer);
        escrow.openDispute(id, 0);
    }

    function test_Event_DisputeResolved_And_Paid() public {
        _toDisputed(id, 0);
        _e();
        emit FreelanceEscrow.DisputeResolved(id, 0, 2_000_000, 3_000_000);
        _e();
        emit FreelanceEscrow.Credited(client, 2_000_000, id);
        _e();
        emit FreelanceEscrow.Credited(p1, 2_100_000, id);
        _e();
        emit FreelanceEscrow.Credited(p2, 900_000, id);
        _e();
        emit FreelanceEscrow.MilestonePaid(id, 0, 3_000_000, 2_000_000);
        _resolve(id, 0, 2_000_000);
    }

    function test_Event_DisputeTimedOut_ThenResolved() public {
        _toDisputed(id, 0);
        vm.warp(block.timestamp + 30 days);
        _e();
        emit FreelanceEscrow.DisputeTimedOut(id, 0);
        _e();
        emit FreelanceEscrow.DisputeResolved(id, 0, 2_500_000, 2_500_000);
        _e();
        emit FreelanceEscrow.MilestonePaid(id, 0, 2_500_000, 2_500_000);
        vm.prank(stranger);
        escrow.resolveDisputeByTimeout(id, 0);
    }

    function test_Event_MilestoneRefunded_Credited() public {
        _start(id, 0);
        vm.warp(block.timestamp + DELIVERY + 1);
        _e();
        emit FreelanceEscrow.Credited(client, 5_000_000, id);
        _e();
        emit FreelanceEscrow.MilestoneRefunded(id, 0, 5_000_000);
        _e();
        emit FreelanceEscrow.MilestoneUnlocked(id, 1, block.timestamp);
        _refundM(id, 0);
    }

    function test_Event_RefundAfterRejection() public {
        _toRejected(id, 0);
        vm.warp(block.timestamp + 7 days);
        _e();
        emit FreelanceEscrow.MilestoneRefunded(id, 0, 5_000_000);
        vm.prank(client);
        escrow.refundAfterRejection(id, 0);
    }

    function test_Event_Withdrawn() public {
        _toDelivered(id, 0);
        _approveM(id, 0);
        vm.expectEmit(true, false, false, true, address(escrow));
        emit FreelanceEscrow.Withdrawn(p1, 3_500_000);
        vm.prank(p1);
        escrow.withdraw();
    }

    function test_Event_DeclineJob_Then_JobCompleted() public {
        _e();
        emit FreelanceEscrow.JobDeclined(id);
        _e();
        emit FreelanceEscrow.MilestoneRefunded(id, 0, 5_000_000);
        _e();
        emit FreelanceEscrow.MilestoneRefunded(id, 1, 5_000_000);
        _e();
        emit FreelanceEscrow.JobCompleted(id);
        vm.prank(freelancer);
        escrow.declineJob(id);
    }

    function test_Event_JobCompleted_OnFinalPayment() public {
        _toDelivered(id, 0);
        _approveM(id, 0);
        _toDelivered(id, 1);
        _e();
        emit FreelanceEscrow.MilestonePaid(id, 1, 5_000_000, 0);
        _e();
        emit FreelanceEscrow.JobCompleted(id);
        _approveM(id, 1);
    }

    function test_Revert_CreateJob_Unfunded() public {
        FreelanceEscrow.MilestoneInput[] memory ms = _evenInputs(1, REVISIONS);
        vm.prank(stranger);
        vm.expectRevert();
        escrow.createJob(freelancer, arbiter, TOTAL, ms);
    }
}
