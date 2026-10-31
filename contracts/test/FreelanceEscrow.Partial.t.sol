// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FreelanceEscrow} from "../FreelanceEscrow.sol";
import {FreelanceEscrowPartialBase} from "./FreelanceEscrow.PartialBase.t.sol";

/// @notice proposePartial / declinePartial / cancelPartial: the non-settling half of the proposal flow.
contract FreelanceEscrowPartialTest is FreelanceEscrowPartialBase {
    function _invalidRefund() internal pure returns (bytes memory) {
        return _sel(FreelanceEscrow.InvalidRefund.selector);
    }

    // ------------------------------------------------------------------ propose: happy path

    function test_Propose_StoresProposal_StateStaysDelivered() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_234_567);
        _assertState(id, 0, DELIVERED);
        assertEq(_proposed(id, 0), 1_234_567, "proposedRefund");
        assertFalse(_ms(id, 0).rejectedFinal);
    }

    function test_Propose_EmitsPartialProposed() public {
        _toDelivered(id, 0);
        _e();
        emit FreelanceEscrow.PartialProposed(id, 0, 777);
        _propose(id, 0, 777);
    }

    function test_Propose_MovesNoMoney_AccountingUnchanged() public {
        _toDelivered(id, 0);
        uint256 bal = usdc.balanceOf(address(escrow));
        FreelanceEscrow.JobView memory before_ = escrow.getJob(id);
        _propose(id, 0, 1_000_000);

        assertEq(usdc.balanceOf(address(escrow)), bal, "escrow balance");
        assertEq(usdc.balanceOf(client), 1e15 - TOTAL, "client wallet");
        FreelanceEscrow.JobView memory after_ = escrow.getJob(id);
        assertEq(after_.paid, before_.paid, "paid");
        assertEq(after_.refunded, before_.refunded, "refunded");
        assertEq(after_.remaining, before_.remaining, "remaining");
        assertEq(escrow.totalRemaining(), TOTAL, "totalRemaining");
        assertEq(escrow.totalClaimable(), 0, "totalClaimable");
        assertEq(_claim(client), 0);
        assertEq(_claim(p1), 0);
        assertEq(_claim(p2), 0);
    }

    function test_Propose_Reproposal_Overwrites() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000);
        _propose(id, 0, 2_000);
        assertEq(_proposed(id, 0), 2_000);
        _propose(id, 0, 500); // can go lower too
        assertEq(_proposed(id, 0), 500);
    }

    function test_Propose_Reproposal_EmitsEachTime() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000);
        _e();
        emit FreelanceEscrow.PartialProposed(id, 0, 2_000);
        _propose(id, 0, 2_000);
    }

    function test_Propose_AfterReviewPeriodEnded_StillAllowed() public {
        _toDelivered(id, 0);
        vm.warp(block.timestamp + REVIEW + 1 days);
        _propose(id, 0, 42);
        assertEq(_proposed(id, 0), 42);
    }

    // ------------------------------------------------------------------ propose: bounds

    function test_Propose_Revert_ZeroRefund() public {
        _toDelivered(id, 0);
        _proposeRevert(_invalidRefund(), id, 0, 0);
    }

    function test_Propose_Revert_RefundEqualsAmount() public {
        _toDelivered(id, 0);
        _proposeRevert(_invalidRefund(), id, 0, AMT);
    }

    function test_Propose_Revert_RefundAboveAmount() public {
        _toDelivered(id, 0);
        _proposeRevert(_invalidRefund(), id, 0, AMT + 1);
        _proposeRevert(_invalidRefund(), id, 0, type(uint256).max);
    }

    function test_Propose_Edges_OneAndAmountMinusOneSucceed() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1);
        assertEq(_proposed(id, 0), 1);
        _propose(id, 0, AMT - 1);
        assertEq(_proposed(id, 0), AMT - 1);
    }

    function test_Propose_Revert_FailedProposalKeepsPreviousOne() public {
        _toDelivered(id, 0);
        _propose(id, 0, 900);
        _proposeRevert(_invalidRefund(), id, 0, AMT);
        assertEq(_proposed(id, 0), 900, "previous proposal intact");
    }

    function test_Propose_Revert_AmountOneMilestoneCannotBeProposed() public {
        uint256 tiny = _createN(2, 2); // milestone amounts 1 and 1
        assertEq(_ms(tiny, 0).amount, 1);
        _toDelivered(tiny, 0);
        _proposeRevert(_invalidRefund(), tiny, 0, 0);
        _proposeRevert(_invalidRefund(), tiny, 0, 1);
        _proposeRevert(_invalidRefund(), tiny, 0, 2);
    }

    function testFuzz_Propose_BoundsExact(uint256 refund) public {
        _toDelivered(id, 0);
        if (refund == 0 || refund >= AMT) {
            _proposeRevert(_invalidRefund(), id, 0, refund);
            assertEq(_proposed(id, 0), 0);
        } else {
            _propose(id, 0, refund);
            assertEq(_proposed(id, 0), refund);
        }
    }

    // ------------------------------------------------------------------ propose: access + state

    function test_Propose_Revert_FreelancerUnauthorized() public {
        _toDelivered(id, 0);
        vm.prank(freelancer);
        vm.expectRevert(_unauthorized());
        escrow.proposePartial(id, 0, 1000);
    }

    function test_Propose_Revert_ArbiterUnauthorized() public {
        _toDelivered(id, 0);
        vm.prank(arbiter);
        vm.expectRevert(_unauthorized());
        escrow.proposePartial(id, 0, 1000);
    }

    function test_Propose_Revert_PayeeUnauthorized() public {
        _toDelivered(id, 0);
        vm.prank(p1);
        vm.expectRevert(_unauthorized());
        escrow.proposePartial(id, 0, 1000);
    }

    function test_Propose_Revert_StrangerUnauthorized() public {
        _toDelivered(id, 0);
        vm.prank(stranger);
        vm.expectRevert(_unauthorized());
        escrow.proposePartial(id, 0, 1000);
    }

    function test_Propose_Revert_UnknownJobOrMilestone() public {
        _proposeRevert(abi.encodeWithSelector(FreelanceEscrow.JobNotFound.selector, 99), 99, 0, 1);
        _proposeRevert(abi.encodeWithSelector(FreelanceEscrow.MilestoneNotFound.selector, 2), id, 2, 1);
    }

    function test_Propose_Revert_Pending() public {
        _proposeRevert(_badState(PENDING), id, 1, 1000);
    }

    function test_Propose_Revert_InProgress() public {
        _start(id, 0);
        _proposeRevert(_badState(IN_PROGRESS), id, 0, 1000);
    }

    function test_Propose_Revert_InRevision() public {
        _toDelivered(id, 0);
        _revise(id, 0);
        _proposeRevert(_badState(IN_REVISION), id, 0, 1000);
    }

    function test_Propose_Revert_Disputed() public {
        _toDisputed(id, 0);
        _proposeRevert(_badState(DISPUTED), id, 0, 1000);
    }

    function test_Propose_Revert_Paid() public {
        _toDelivered(id, 0);
        _approveM(id, 0);
        _proposeRevert(_badState(PAID), id, 0, 1000);
    }

    function test_Propose_Revert_Refunded() public {
        _start(id, 0);
        vm.warp(block.timestamp + DELIVERY + 1);
        _refundM(id, 0);
        _proposeRevert(_badState(REFUNDED), id, 0, 1000);
    }

    // ------------------------------------------------------------------ proposal does not block other rights

    function test_Propose_DoesNotBlock_FullApprove() public {
        _toDelivered(id, 0);
        _propose(id, 0, 3_000_000);
        _approveM(id, 0);
        _assertState(id, 0, PAID);
        FreelanceEscrow.JobView memory j = escrow.getJob(id);
        assertEq(j.paid, AMT, "payees paid in full");
        assertEq(j.refunded, 0, "no refund");
        assertEq(_claim(client), 0);
        assertEq(_claim(p1) + _claim(p2), AMT);
        assertEq(_proposed(id, 0), 0, "proposal not exposed after payout");
    }

    function test_Propose_DoesNotBlock_RequestRevision() public {
        _toDelivered(id, 0);
        _propose(id, 0, 3_000_000);
        _revise(id, 0);
        _assertState(id, 0, IN_REVISION);
        assertEq(_proposed(id, 0), 0, "hidden outside Delivered");
    }

    function test_Propose_DoesNotBlock_RejectDelivery() public {
        _toDelivered(id, 0);
        _revise(id, 0);
        _deliver(id, 0);
        _propose(id, 0, 3_000_000);
        _reject(id, 0);
        assertTrue(_ms(id, 0).rejectedFinal);
        _assertState(id, 0, DELIVERED);
    }

    function test_Propose_DoesNotBlock_ClientOpenDispute() public {
        _toDelivered(id, 0);
        _propose(id, 0, 3_000_000);
        _clientDispute(id, 0);
        _assertState(id, 0, DISPUTED);
        assertEq(_proposed(id, 0), 0, "hidden outside Delivered");
        _resolve(id, 0, 1_000_000);
        _assertState(id, 0, PAID);
        assertEq(_claim(client), 1_000_000, "arbiter's refund governs, not proposal");
    }

    function test_Propose_DoesNotBlock_AutoApproveAfterReview_PayeesPaidInFull() public {
        _toDelivered(id, 0);
        _propose(id, 0, 3_000_000);
        vm.warp(block.timestamp + REVIEW);
        _autoApproveBy(stranger, id, 0);
        _assertState(id, 0, PAID);
        FreelanceEscrow.JobView memory j = escrow.getJob(id);
        assertEq(j.paid, AMT, "paid in full");
        assertEq(j.refunded, 0, "proposal ignored");
        assertEq(_claim(client), 0);
        assertEq(_claim(p1) + _claim(p2), AMT);
        (, uint16[] memory shares) = escrow.getPayees(id, 0);
        uint256[] memory exp = _split(AMT, shares);
        assertEq(_claim(p1), exp[0]);
        assertEq(_claim(p2), exp[1]);
    }

    function test_Propose_AutoApproveBeforeReviewEnd_StillTooEarly() public {
        _toDelivered(id, 0);
        _propose(id, 0, 3_000_000);
        vm.prank(stranger);
        vm.expectRevert(_sel(FreelanceEscrow.TooEarly.selector));
        escrow.autoApprove(id, 0);
    }

    // ------------------------------------------------------------------ decline

    function test_Decline_ClearsProposal_EmitsEvent() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000_000);
        _e();
        emit FreelanceEscrow.PartialDeclined(id, 0);
        _decline(id, 0);
        assertEq(_proposed(id, 0), 0);
        _assertState(id, 0, DELIVERED);
        assertEq(escrow.totalClaimable(), 0, "no money moved");
    }

    function test_Decline_ThenAccept_NoProposal() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000_000);
        _decline(id, 0);
        _acceptRevert(_noProposal(), id, 0, 1_000_000);
    }

    function test_Decline_ClientCanProposeAgain() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000_000);
        _decline(id, 0);
        _propose(id, 0, 1_500_000);
        assertEq(_proposed(id, 0), 1_500_000);
        _accept(id, 0, 1_500_000);
        _assertState(id, 0, PAID);
    }

    function test_Decline_Revert_NoProposal() public {
        _toDelivered(id, 0);
        vm.prank(freelancer);
        vm.expectRevert(_noProposal());
        escrow.declinePartial(id, 0);
    }

    function test_Decline_Revert_SecondDeclineNoProposal() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000_000);
        _decline(id, 0);
        vm.prank(freelancer);
        vm.expectRevert(_noProposal());
        escrow.declinePartial(id, 0);
    }

    function test_Decline_Revert_ClientUnauthorized() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000_000);
        vm.prank(client);
        vm.expectRevert(_unauthorized());
        escrow.declinePartial(id, 0);
        assertEq(_proposed(id, 0), 1_000_000);
    }

    function test_Decline_Revert_ArbiterPayeeStrangerUnauthorized() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000_000);
        address[3] memory who = [arbiter, p1, stranger];
        for (uint256 i; i < who.length; ++i) {
            vm.prank(who[i]);
            vm.expectRevert(_unauthorized());
            escrow.declinePartial(id, 0);
        }
        assertEq(_proposed(id, 0), 1_000_000);
    }

    function test_Decline_Revert_NotDelivered() public {
        _start(id, 0);
        vm.prank(freelancer);
        vm.expectRevert(_badState(IN_PROGRESS));
        escrow.declinePartial(id, 0);
        vm.prank(freelancer);
        vm.expectRevert(_badState(PENDING));
        escrow.declinePartial(id, 1);
    }

    function test_AfterDecline_RightsUnchanged_Approve() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000_000);
        _decline(id, 0);
        _approveM(id, 0);
        _assertState(id, 0, PAID);
        assertEq(escrow.getJob(id).paid, AMT);
    }

    function test_AfterDecline_RightsUnchanged_Dispute() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000_000);
        _decline(id, 0);
        _clientDispute(id, 0);
        _assertState(id, 0, DISPUTED);
    }

    function test_AfterDecline_RightsUnchanged_AutoApprove() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000_000);
        _decline(id, 0);
        vm.warp(block.timestamp + REVIEW);
        _autoApproveBy(stranger, id, 0);
        _assertState(id, 0, PAID);
        assertEq(escrow.getJob(id).paid, AMT);
        assertEq(escrow.getJob(id).refunded, 0);
    }

    // ------------------------------------------------------------------ cancel

    function test_Cancel_ClearsProposal_EmitsEvent() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000_000);
        _e();
        emit FreelanceEscrow.PartialCancelled(id, 0);
        _cancel(id, 0);
        assertEq(_proposed(id, 0), 0);
        _assertState(id, 0, DELIVERED);
        assertEq(escrow.totalClaimable(), 0, "no money moved");
    }

    function test_Cancel_ThenAccept_NoProposal() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000_000);
        _cancel(id, 0);
        _acceptRevert(_noProposal(), id, 0, 1_000_000);
    }

    function test_Cancel_Revert_NoProposal() public {
        _toDelivered(id, 0);
        vm.prank(client);
        vm.expectRevert(_noProposal());
        escrow.cancelPartial(id, 0);
    }

    function test_Cancel_Revert_SecondCancelNoProposal() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000_000);
        _cancel(id, 0);
        vm.prank(client);
        vm.expectRevert(_noProposal());
        escrow.cancelPartial(id, 0);
    }

    function test_Cancel_Revert_FreelancerUnauthorized() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000_000);
        vm.prank(freelancer);
        vm.expectRevert(_unauthorized());
        escrow.cancelPartial(id, 0);
        assertEq(_proposed(id, 0), 1_000_000);
    }

    function test_Cancel_Revert_ArbiterPayeeStrangerUnauthorized() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000_000);
        address[3] memory who = [arbiter, p1, stranger];
        for (uint256 i; i < who.length; ++i) {
            vm.prank(who[i]);
            vm.expectRevert(_unauthorized());
            escrow.cancelPartial(id, 0);
        }
        assertEq(_proposed(id, 0), 1_000_000);
    }

    function test_Cancel_Revert_NotDelivered() public {
        _start(id, 0);
        vm.prank(client);
        vm.expectRevert(_badState(IN_PROGRESS));
        escrow.cancelPartial(id, 0);
    }

    function test_AfterCancel_RightsUnchanged_Approve() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000_000);
        _cancel(id, 0);
        _approveM(id, 0);
        _assertState(id, 0, PAID);
        assertEq(escrow.getJob(id).paid, AMT);
    }

    function test_AfterCancel_RightsUnchanged_Dispute() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000_000);
        _cancel(id, 0);
        _clientDispute(id, 0);
        _assertState(id, 0, DISPUTED);
    }

    function test_AfterCancel_RightsUnchanged_AutoApprove() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000_000);
        _cancel(id, 0);
        vm.warp(block.timestamp + REVIEW);
        _autoApproveBy(p1, id, 0);
        _assertState(id, 0, PAID);
        assertEq(escrow.getJob(id).refunded, 0);
    }
}
