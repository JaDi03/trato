// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
import {FreelanceEscrow} from "../FreelanceEscrow.sol";
import {FreelanceEscrowPartialBase} from "./FreelanceEscrow.PartialBase.t.sol";

/// @notice acceptPartial: Delivered -> Approved -> Paid in one tx with a client/payee split.
contract FreelanceEscrowAcceptTest is FreelanceEscrowPartialBase {
    uint256 internal constant REFUND = 1_234_567;

    function _mismatch(uint256 proposed, uint256 expected) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FreelanceEscrow.ProposalMismatch.selector, proposed, expected);
    }

    function _proposeAccept(uint256 jobId, uint256 m, uint256 refund) internal {
        _propose(jobId, m, refund);
        _accept(jobId, m, refund);
    }

    // ------------------------------------------------------------------ happy path

    function test_Accept_SettlesInOneTx() public {
        _toDelivered(id, 0);
        _propose(id, 0, REFUND);
        _accept(id, 0, REFUND);

        _assertState(id, 0, PAID);
        FreelanceEscrow.JobView memory j = escrow.getJob(id);
        assertEq(j.paid, AMT - REFUND, "job.paid");
        assertEq(j.refunded, REFUND, "job.refunded");
        assertEq(j.remaining, TOTAL - AMT, "job.remaining");
        assertFalse(j.completed, "not completed");
        assertEq(escrow.totalRemaining(), TOTAL - AMT, "totalRemaining");
        assertEq(escrow.totalClaimable(), AMT, "totalClaimable");
        assertEq(usdc.balanceOf(address(escrow)), escrow.totalRemaining() + escrow.totalClaimable(), "balance");
        assertEq(_proposed(id, 0), 0, "proposal consumed");
    }

    function test_Accept_CreditsClientAndPayeesBySharesOnly() public {
        _toDelivered(id, 0);
        _proposeAccept(id, 0, REFUND);
        (, uint16[] memory shares) = escrow.getPayees(id, 0);
        uint256[] memory exp = _split(AMT - REFUND, shares);
        assertEq(_claim(p1), exp[0], "p1");
        assertEq(_claim(p2), exp[1], "p2");
        assertEq(_claim(p1) + _claim(p2), AMT - REFUND);
        assertEq(_claim(client), REFUND, "client");
        assertEq(_claim(freelancer), 0, "freelancer not credited");
        assertEq(_claim(arbiter), 0, "arbiter not credited");
    }

    function test_Accept_UnlocksNextMilestone() public {
        _toDelivered(id, 0);
        assertEq(_ms(id, 1).unlockedAt, 0);
        _proposeAccept(id, 0, REFUND);
        assertEq(_ms(id, 1).unlockedAt, block.timestamp, "next unlocked");
        _assertState(id, 1, PENDING);
        _start(id, 1); // startable
        _assertState(id, 1, IN_PROGRESS);
    }

    function test_Accept_EmitsEventsInOrder() public {
        _toDelivered(id, 0);
        _propose(id, 0, REFUND);
        uint256 payeeAmt = AMT - REFUND;
        (, uint16[] memory shares) = escrow.getPayees(id, 0);
        uint256[] memory exp = _split(payeeAmt, shares);

        _e();
        emit FreelanceEscrow.PartialAccepted(id, 0, REFUND);
        _e();
        emit FreelanceEscrow.MilestoneApproved(id, 0, false);
        _e();
        emit FreelanceEscrow.Credited(client, REFUND, id);
        _e();
        emit FreelanceEscrow.Credited(p1, exp[0], id);
        _e();
        emit FreelanceEscrow.Credited(p2, exp[1], id);
        _e();
        emit FreelanceEscrow.MilestonePaid(id, 0, payeeAmt, REFUND);
        _e();
        emit FreelanceEscrow.MilestoneUnlocked(id, 1, block.timestamp);
        _accept(id, 0, REFUND);
    }

    function test_Accept_ExactEventSequence() public {
        _toDelivered(id, 0);
        _propose(id, 0, REFUND);
        vm.recordLogs();
        _accept(id, 0, REFUND);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32[7] memory want = [
            keccak256("PartialAccepted(uint256,uint256,uint256)"),
            keccak256("MilestoneApproved(uint256,uint256,bool)"),
            keccak256("Credited(address,uint256,uint256)"),
            keccak256("Credited(address,uint256,uint256)"),
            keccak256("Credited(address,uint256,uint256)"),
            keccak256("MilestonePaid(uint256,uint256,uint256,uint256)"),
            keccak256("MilestoneUnlocked(uint256,uint256,uint256)")
        ];
        assertEq(logs.length, want.length, "no extra events");
        for (uint256 i; i < want.length; ++i) {
            assertEq(logs[i].topics[0], want[i], "event order");
        }
        // client is credited before the first payee
        assertEq(address(uint160(uint256(logs[2].topics[1]))), client);
        assertEq(address(uint160(uint256(logs[3].topics[1]))), p1);
        assertEq(address(uint160(uint256(logs[4].topics[1]))), p2);
    }

    function test_Accept_LastMilestone_CompletesJob() public {
        uint256 one = _createN(TOTAL, 1);
        _toDelivered(one, 0);
        _propose(one, 0, REFUND);
        _e();
        emit FreelanceEscrow.JobCompleted(one);
        _accept(one, 0, REFUND);
        FreelanceEscrow.JobView memory j = escrow.getJob(one);
        assertTrue(j.completed);
        assertEq(j.remaining, 0);
        assertEq(j.paid + j.refunded, TOTAL);
    }

    function test_Accept_LastMilestone_JobCompletedIsFinalEvent() public {
        uint256 one = _createN(TOTAL, 1);
        _toDelivered(one, 0);
        _propose(one, 0, REFUND);
        vm.recordLogs();
        _accept(one, 0, REFUND);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 7);
        assertEq(logs[6].topics[0], keccak256("JobCompleted(uint256)"));
        assertEq(logs[5].topics[0], keccak256("MilestonePaid(uint256,uint256,uint256,uint256)"));
    }

    function test_Accept_BothMilestones_CompletesJobWithMixedPaths() public {
        _toDelivered(id, 0);
        _approveM(id, 0);
        _toDelivered(id, 1);
        _proposeAccept(id, 1, 999_999);
        FreelanceEscrow.JobView memory j = escrow.getJob(id);
        assertTrue(j.completed);
        assertEq(j.paid, AMT + AMT - 999_999);
        assertEq(j.refunded, 999_999);
        assertEq(usdc.balanceOf(address(escrow)), escrow.totalClaimable());
    }

    function test_Accept_Edges_OneAndAmountMinusOne() public {
        _toDelivered(id, 0);
        _proposeAccept(id, 0, 1);
        assertEq(_claim(client), 1);
        assertEq(_claim(p1) + _claim(p2), AMT - 1);
        _toDelivered(id, 1);
        _proposeAccept(id, 1, AMT - 1);
        assertEq(_claim(client), AMT);
        assertEq(escrow.getJob(id).refunded, AMT);
        assertEq(escrow.totalRemaining(), 0);
        assertEq(usdc.balanceOf(address(escrow)), escrow.totalClaimable());
    }

    function test_Accept_ClientAndPayeesCanWithdraw() public {
        _toDelivered(id, 0);
        _proposeAccept(id, 0, REFUND);
        (, uint16[] memory shares) = escrow.getPayees(id, 0);
        uint256[] memory exp = _split(AMT - REFUND, shares);
        uint256 clientBefore = usdc.balanceOf(client);

        vm.prank(client);
        escrow.withdraw();
        vm.prank(p1);
        escrow.withdraw();
        vm.prank(p2);
        escrow.withdraw();

        assertEq(usdc.balanceOf(client) - clientBefore, REFUND, "client got refund");
        assertEq(usdc.balanceOf(p1), exp[0], "p1");
        assertEq(usdc.balanceOf(p2), exp[1], "p2");
        assertEq(escrow.totalClaimable(), 0);
        assertEq(usdc.balanceOf(address(escrow)), TOTAL - AMT, "only milestone 1 left");
        assertEq(usdc.balanceOf(address(escrow)), escrow.totalRemaining());
    }

    // ------------------------------------------------------------------ odd amounts / split conservation

    function test_Accept_OddAmount_LastPayeeTakesRemainder() public {
        uint256 odd = _createThreePayee(10_000_001, 3333, 3333, 3334);
        _toDelivered(odd, 0);
        _proposeAccept(odd, 0, 1);
        uint256 payeeAmt = 10_000_000;
        (, uint16[] memory shares) = escrow.getPayees(odd, 0);
        uint256[] memory exp = _split(payeeAmt, shares);
        assertEq(_claim(p1), exp[0]);
        assertEq(_claim(p2), exp[1]);
        assertEq(_claim(p3), exp[2]);
        assertEq(_claim(p1) + _claim(p2) + _claim(p3), payeeAmt, "payees conserve");
        assertEq(_claim(client), 1);
        assertEq(escrow.totalClaimable(), 10_000_001);
        assertEq(escrow.totalRemaining(), TOTAL, "only setUp job still escrowed");
        assertEq(escrow.getJob(odd).remaining, 0);
    }

    function test_Accept_TinyPayeeAmount_RemainderToLast() public {
        // amount 7, refund 6 => payees share 1 unit: floors to 0 for early payees, last gets 1.
        uint256 tiny = _createThreePayee(7, 3333, 3333, 3334);
        _toDelivered(tiny, 0);
        _proposeAccept(tiny, 0, 6);
        assertEq(_claim(p1), 0);
        assertEq(_claim(p2), 0);
        assertEq(_claim(p3), 1);
        assertEq(_claim(client), 6);
        assertTrue(escrow.getJob(tiny).completed);
    }

    function testFuzz_Accept_SplitConservesExactly(uint256 amount, uint256 refund, uint16 a, uint16 b) public {
        amount = bound(amount, 2, 1e12);
        refund = bound(refund, 1, amount - 1);
        uint16 s1 = uint16(bound(a, 1, 9998));
        uint16 s2 = uint16(bound(b, 1, 9999 - s1));
        uint16 s3 = 10_000 - s1 - s2;
        uint256 jid = _createThreePayee(amount, s1, s2, s3);
        _toDelivered(jid, 0);
        _propose(jid, 0, refund);
        _accept(jid, 0, refund);

        uint16[] memory shares = new uint16[](3);
        shares[0] = s1;
        shares[1] = s2;
        shares[2] = s3;
        uint256[] memory exp = _split(amount - refund, shares);
        assertEq(_claim(p1), exp[0], "p1");
        assertEq(_claim(p2), exp[1], "p2");
        assertEq(_claim(p3), exp[2], "p3");
        assertEq(_claim(p1) + _claim(p2) + _claim(p3), amount - refund, "payees conserve");
        assertEq(_claim(client), refund, "client");
        assertEq(escrow.totalClaimable(), amount, "totalClaimable");
        assertEq(escrow.totalRemaining(), TOTAL, "totalRemaining (setUp job only)");
        assertEq(usdc.balanceOf(address(escrow)), amount + TOTAL, "balance conserved");
        FreelanceEscrow.JobView memory j = escrow.getJob(jid);
        assertEq(j.paid, amount - refund);
        assertEq(j.refunded, refund);
        assertEq(j.remaining, 0);
        assertTrue(j.completed);
    }

    // ------------------------------------------------------------------ access

    function test_Accept_Revert_ClientUnauthorized() public {
        _toDelivered(id, 0);
        _propose(id, 0, REFUND);
        vm.prank(client);
        vm.expectRevert(_unauthorized());
        escrow.acceptPartial(id, 0, REFUND);
        _assertState(id, 0, DELIVERED);
        assertEq(_proposed(id, 0), REFUND);
    }

    function test_Accept_Revert_ArbiterPayeeStrangerUnauthorized() public {
        _toDelivered(id, 0);
        _propose(id, 0, REFUND);
        address[3] memory who = [arbiter, p1, stranger];
        for (uint256 i; i < who.length; ++i) {
            vm.prank(who[i]);
            vm.expectRevert(_unauthorized());
            escrow.acceptPartial(id, 0, REFUND);
        }
        _assertState(id, 0, DELIVERED);
        assertEq(escrow.totalClaimable(), 0);
    }

    function test_Accept_Revert_UnknownJobOrMilestone() public {
        _acceptRevert(abi.encodeWithSelector(FreelanceEscrow.JobNotFound.selector, 99), 99, 0, 1);
        _acceptRevert(abi.encodeWithSelector(FreelanceEscrow.MilestoneNotFound.selector, 2), id, 2, 1);
    }

    // ------------------------------------------------------------------ no proposal / mismatch

    function test_Accept_Revert_NoProposal() public {
        _toDelivered(id, 0);
        _acceptRevert(_noProposal(), id, 0, 0);
        _acceptRevert(_noProposal(), id, 0, 1000);
    }

    function test_Accept_Revert_WrongExpected_ProposalMismatch_NothingMoves() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000_000);
        _propose(id, 0, 2_000_000); // client changes terms (front-run)
        _acceptRevert(_mismatch(2_000_000, 1_000_000), id, 0, 1_000_000);

        _assertState(id, 0, DELIVERED);
        assertEq(_proposed(id, 0), 2_000_000, "proposal intact");
        assertEq(escrow.totalClaimable(), 0);
        assertEq(escrow.totalRemaining(), TOTAL);
        assertEq(escrow.getJob(id).paid, 0);
        assertEq(escrow.getJob(id).refunded, 0);
        // the up-to-date terms still work
        _accept(id, 0, 2_000_000);
        assertEq(_claim(client), 2_000_000);
    }

    function test_Accept_Revert_ExpectedZeroWithProposal_Mismatch() public {
        _toDelivered(id, 0);
        _propose(id, 0, 1_000_000);
        _acceptRevert(_mismatch(1_000_000, 0), id, 0, 0);
    }

    function testFuzz_Accept_Revert_AnyWrongExpected(uint256 proposed, uint256 expected) public {
        proposed = bound(proposed, 1, AMT - 1);
        vm.assume(expected != proposed);
        _toDelivered(id, 0);
        _propose(id, 0, proposed);
        _acceptRevert(_mismatch(proposed, expected), id, 0, expected);
        _assertState(id, 0, DELIVERED);
        assertEq(escrow.totalClaimable(), 0);
    }

    // ------------------------------------------------------------------ timing / rejection

    function test_Accept_AfterReviewPeriodEnded_StillWorks() public {
        _toDelivered(id, 0);
        _propose(id, 0, REFUND);
        vm.warp(block.timestamp + REVIEW + 30 days);
        _accept(id, 0, REFUND);
        _assertState(id, 0, PAID);
        assertEq(_claim(client), REFUND);
    }

    function test_Accept_AfterFinalRejection_WorksBeforeRefund() public {
        _toRejected(id, 0);
        assertTrue(_ms(id, 0).rejectedFinal);
        _propose(id, 0, REFUND);
        vm.warp(block.timestamp + 7 days); // refund window open but not exercised
        _accept(id, 0, REFUND);
        _assertState(id, 0, PAID);
        assertEq(_claim(client), REFUND);
        assertEq(_claim(p1) + _claim(p2), AMT - REFUND);
    }

    function test_Accept_ProposedBeforeFinalRejection_WorksAfterRejection() public {
        _toDelivered(id, 0);
        _revise(id, 0);
        _deliver(id, 0);
        _propose(id, 0, REFUND);
        _reject(id, 0);
        _accept(id, 0, REFUND);
        _assertState(id, 0, PAID);
    }

    function test_Accept_Revert_AfterRefundAfterRejection() public {
        _toRejected(id, 0);
        _propose(id, 0, REFUND);
        vm.warp(block.timestamp + 7 days);
        vm.prank(client);
        escrow.refundAfterRejection(id, 0);
        _assertState(id, 0, REFUNDED);
        _acceptRevert(_badState(REFUNDED), id, 0, REFUND);
        assertEq(_claim(client), AMT, "client got whole milestone, nothing else");
        assertEq(_claim(p1) + _claim(p2), 0);
    }

    // ------------------------------------------------------------------ wrong state

    function test_Accept_Revert_Pending() public {
        _acceptRevert(_badState(PENDING), id, 1, 1);
    }

    function test_Accept_Revert_InProgress() public {
        _start(id, 0);
        _acceptRevert(_badState(IN_PROGRESS), id, 0, 1);
    }

    function test_Accept_Revert_SecondAcceptOnPaid() public {
        _toDelivered(id, 0);
        _proposeAccept(id, 0, REFUND);
        _acceptRevert(_badState(PAID), id, 0, REFUND);
        assertEq(_claim(client), REFUND, "no double credit");
        assertEq(escrow.totalClaimable(), AMT);
    }

    function test_Accept_Revert_PaidViaFullApprove() public {
        _toDelivered(id, 0);
        _propose(id, 0, REFUND);
        _approveM(id, 0);
        _acceptRevert(_badState(PAID), id, 0, REFUND);
        assertEq(_claim(client), 0);
    }

    function test_Accept_Revert_InRevision() public {
        _toDelivered(id, 0);
        _propose(id, 0, REFUND);
        _revise(id, 0);
        _acceptRevert(_badState(IN_REVISION), id, 0, REFUND);
    }

    function test_Accept_Revert_Disputed() public {
        _toDelivered(id, 0);
        _propose(id, 0, REFUND);
        _clientDispute(id, 0);
        _acceptRevert(_badState(DISPUTED), id, 0, REFUND);
    }

    function test_Accept_Revert_Refunded() public {
        _start(id, 0);
        vm.warp(block.timestamp + DELIVERY + 1);
        _refundM(id, 0);
        _acceptRevert(_badState(REFUNDED), id, 0, 1);
    }

    function test_AfterAccept_ProposeDeclineCancelRevertInvalidState() public {
        _toDelivered(id, 0);
        _proposeAccept(id, 0, REFUND);
        _proposeRevert(_badState(PAID), id, 0, REFUND);
        vm.prank(freelancer);
        vm.expectRevert(_badState(PAID));
        escrow.declinePartial(id, 0);
        vm.prank(client);
        vm.expectRevert(_badState(PAID));
        escrow.cancelPartial(id, 0);
    }

    // ------------------------------------------------------------------ stale proposal

    function test_Stale_ProposeReviseRedeliver_ProposalCleared() public {
        _toDelivered(id, 0);
        _propose(id, 0, REFUND);
        _revise(id, 0);
        _deliver(id, 0);
        _assertState(id, 0, DELIVERED);
        assertEq(_proposed(id, 0), 0, "stale proposal cleared on redeliver");
        _acceptRevert(_noProposal(), id, 0, REFUND);
        assertEq(escrow.totalClaimable(), 0);
    }

    function test_Stale_FreshProposalAfterRedeliverWorks() public {
        _toDelivered(id, 0);
        _propose(id, 0, REFUND);
        _revise(id, 0);
        _deliver(id, 0);
        _propose(id, 0, 777_777);
        _acceptRevert(_mismatch(777_777, REFUND), id, 0, REFUND);
        _accept(id, 0, 777_777);
        assertEq(_claim(client), 777_777);
    }
}
