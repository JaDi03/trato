// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FreelanceEscrow} from "../FreelanceEscrow.sol";
import {FreelanceEscrowTestBase} from "./FreelanceEscrow.Base.t.sol";

/// @notice refundMilestone, refundAfterRejection, and declineJob.
contract FreelanceEscrowRefundTest is FreelanceEscrowTestBase {
    uint256 internal id;
    uint256 internal constant AMOUNT = 5_000_000;

    function setUp() public override {
        super.setUp();
        id = _createN(TOTAL, 2);
    }

    // ------------------------------------------------------------ refundMilestone: started work

    function test_Revert_Refund_BeforeAndAtDeadline() public {
        _start(id, 0);
        uint256 dl = _ms(id, 0).deadline;
        vm.warp(dl - 1);
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.TooEarly.selector);
        escrow.refundMilestone(id, 0);
        vm.warp(dl);
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.TooEarly.selector);
        escrow.refundMilestone(id, 0);
    }

    function test_Refund_InProgress_AfterDeadline() public {
        _start(id, 0);
        vm.warp(_ms(id, 0).deadline + 1);
        _refundM(id, 0);
        _assertState(id, 0, REFUNDED);
        assertEq(_claim(client), AMOUNT);
        FreelanceEscrow.JobView memory j = escrow.getJob(id);
        assertEq(j.refunded, AMOUNT);
        assertEq(j.remaining, AMOUNT);
    }

    function test_Refund_InRevision_OnlyAfterFreshDeadline() public {
        _toDelivered(id, 0);
        _revise(id, 0);
        uint256 newDeadline = _ms(id, 0).deadline;
        assertEq(newDeadline, block.timestamp + DELIVERY);
        vm.warp(newDeadline);
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.TooEarly.selector);
        escrow.refundMilestone(id, 0);
        vm.warp(newDeadline + 1);
        _refundM(id, 0);
        _assertState(id, 0, REFUNDED);
        assertEq(_claim(client), AMOUNT);
    }

    function test_SoftDeadline_FreelancerMayDeliverLate_UntilClientRefunds() public {
        _start(id, 0);
        vm.warp(_ms(id, 0).deadline + 2 days);
        _deliver(id, 0);
        _assertState(id, 0, DELIVERED);
        vm.prank(client);
        vm.expectRevert(_badState(DELIVERED));
        escrow.refundMilestone(id, 0);
    }

    function test_RefundedMilestone_CannotBeDelivered() public {
        _start(id, 0);
        vm.warp(_ms(id, 0).deadline + 1);
        _refundM(id, 0);
        vm.prank(freelancer);
        vm.expectRevert(_badState(REFUNDED));
        escrow.deliver(id, 0);
    }

    // ------------------------------------------------------------ refundMilestone: unstarted work

    function test_Refund_Unstarted_OnlyAfterFourteenDays() public {
        uint256 unlocked = _ms(id, 0).unlockedAt;
        vm.warp(unlocked + 14 days);
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.TooEarly.selector);
        escrow.refundMilestone(id, 0);
        vm.warp(unlocked + 14 days + 1);
        _refundM(id, 0);
        _assertState(id, 0, REFUNDED);
        assertEq(_claim(client), AMOUNT);
        // next milestone unlocked by the refund
        assertEq(_ms(id, 1).unlockedAt, block.timestamp);
        vm.prank(freelancer);
        vm.expectRevert(_badState(REFUNDED));
        escrow.startMilestone(id, 0);
    }

    function test_Refund_Unstarted_SecondMilestoneWindowStartsWhenUnlocked() public {
        vm.warp(T0 + 20 days);
        _toDelivered(id, 0);
        _approveM(id, 0);
        uint256 unlocked = _ms(id, 1).unlockedAt;
        assertEq(unlocked, T0 + 20 days);
        vm.warp(unlocked + 14 days);
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.TooEarly.selector);
        escrow.refundMilestone(id, 1);
        vm.warp(unlocked + 14 days + 1);
        _refundM(id, 1);
        _assertState(id, 1, REFUNDED);
        assertTrue(escrow.getJob(id).completed);
    }

    // ------------------------------------------------------------ refundAfterRejection

    function test_Revert_RefundAfterRejection_NotRejectedOrWrongCaller() public {
        _toDelivered(id, 0);
        vm.warp(block.timestamp + 100 days);
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.NotRejected.selector);
        escrow.refundAfterRejection(id, 0);

        uint256 id2 = _createN(TOTAL, 1);
        _toRejected(id2, 0);
        vm.warp(block.timestamp + 8 days);
        address[3] memory bad = [freelancer, arbiter, stranger];
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(bad[i]);
            vm.expectRevert(FreelanceEscrow.Unauthorized.selector);
            escrow.refundAfterRejection(id2, 0);
        }
        // wrong state
        vm.prank(client);
        vm.expectRevert(_badState(PENDING));
        escrow.refundAfterRejection(id, 1);
    }

    function test_RefundAfterRejection_BeforeAndAtSevenDays() public {
        _toRejected(id, 0);
        uint256 rejectedAt = _ms(id, 0).rejectedAt;
        vm.warp(rejectedAt + 7 days - 1);
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.TooEarly.selector);
        escrow.refundAfterRejection(id, 0);

        vm.warp(rejectedAt + 7 days);
        vm.prank(client);
        escrow.refundAfterRejection(id, 0);
        _assertState(id, 0, REFUNDED);
        assertEq(_claim(client), AMOUNT);
    }

    function test_FreelancerDispute_BeforeRefund_BlocksRefund() public {
        _toRejected(id, 0);
        uint256 rejectedAt = _ms(id, 0).rejectedAt;
        vm.warp(rejectedAt + 7 days - 1);
        vm.prank(freelancer);
        escrow.openDispute(id, 0);
        vm.warp(rejectedAt + 7 days + 1);
        vm.prank(client);
        vm.expectRevert(_badState(DISPUTED));
        escrow.refundAfterRejection(id, 0);
        assertEq(_claim(client), 0);
    }

    function test_FreelancerCanDispute_UpToTheRefund() public {
        _toRejected(id, 0);
        uint256 rejectedAt = _ms(id, 0).rejectedAt;
        // long after the 7-day mark, but the client never refunded: freelancer may still dispute
        vm.warp(rejectedAt + 7 days + 60 days);
        vm.prank(freelancer);
        escrow.openDispute(id, 0);
        _assertState(id, 0, DISPUTED);
    }

    function test_FreelancerCannotDispute_AfterRefund() public {
        _toRejected(id, 0);
        vm.warp(block.timestamp + 7 days);
        vm.prank(client);
        escrow.refundAfterRejection(id, 0);
        vm.prank(freelancer);
        vm.expectRevert(_badState(REFUNDED));
        escrow.openDispute(id, 0);
    }

    function test_ClientApproval_BlocksRefundAfterRejection() public {
        _toRejected(id, 0);
        _approveM(id, 0);
        vm.warp(block.timestamp + 8 days);
        vm.prank(client);
        vm.expectRevert(_badState(PAID));
        escrow.refundAfterRejection(id, 0);
    }

    // ------------------------------------------------------------ declineJob

    function test_DeclineJob_RefundsEverythingToClient() public {
        vm.prank(freelancer);
        escrow.declineJob(id);
        assertEq(_claim(client), TOTAL);
        _assertState(id, 0, REFUNDED);
        _assertState(id, 1, REFUNDED);
        FreelanceEscrow.JobView memory j = escrow.getJob(id);
        assertTrue(j.completed);
        assertEq(j.refunded, TOTAL);
        assertEq(j.remaining, 0);
        assertEq(j.paid, 0);
        assertEq(escrow.totalRemaining(), 0);
        assertEq(escrow.totalClaimable(), TOTAL);
    }

    function test_DeclineJob_EmitsDeclinedAndCompleted() public {
        _e();
        emit FreelanceEscrow.JobDeclined(id);
        _e();
        emit FreelanceEscrow.JobCompleted(id);
        vm.prank(freelancer);
        escrow.declineJob(id);
    }

    function test_DeclineJob_ClientCanWithdrawFullDeposit() public {
        uint256 before_ = usdc.balanceOf(client);
        vm.prank(freelancer);
        escrow.declineJob(id);
        vm.prank(client);
        escrow.withdraw();
        assertEq(usdc.balanceOf(client), before_ + TOTAL);
        assertEq(usdc.balanceOf(address(escrow)), 0);
    }

    function test_Revert_DeclineJob_OnlyFreelancer() public {
        address[4] memory bad = [client, arbiter, stranger, p1];
        for (uint256 i; i < bad.length; ++i) {
            vm.prank(bad[i]);
            vm.expectRevert(FreelanceEscrow.Unauthorized.selector);
            escrow.declineJob(id);
        }
    }

    function test_Revert_DeclineJob_AfterStartMilestone() public {
        _start(id, 0);
        vm.prank(freelancer);
        vm.expectRevert(_badState(IN_PROGRESS));
        escrow.declineJob(id);
    }

    function test_Revert_DeclineJob_Twice() public {
        vm.prank(freelancer);
        escrow.declineJob(id);
        vm.prank(freelancer);
        vm.expectRevert(FreelanceEscrow.JobAlreadyCompleted.selector);
        escrow.declineJob(id);
    }

    // ------------------------------------------------------------ second refund on a Refunded milestone

    function test_Revert_RefundMilestone_SecondCallOnRefunded() public {
        _start(id, 0);
        vm.warp(_ms(id, 0).deadline + 1);
        _refundM(id, 0);
        _assertState(id, 0, REFUNDED);

        vm.warp(block.timestamp + 100 days);
        vm.prank(client);
        vm.expectRevert(_badState(REFUNDED));
        escrow.refundMilestone(id, 0);

        // nothing moved on the failed second call
        assertEq(_claim(client), AMOUNT);
        FreelanceEscrow.JobView memory j = escrow.getJob(id);
        assertEq(j.refunded, AMOUNT);
        assertEq(j.remaining, AMOUNT);
        assertEq(escrow.totalClaimable(), AMOUNT);
    }

    function test_Revert_RefundMilestone_SecondCallOnRefundedUnstarted() public {
        vm.warp(T0 + 14 days + 1);
        _refundM(id, 0);
        _assertState(id, 0, REFUNDED);

        vm.prank(client);
        vm.expectRevert(_badState(REFUNDED));
        escrow.refundMilestone(id, 0);
        assertEq(_claim(client), AMOUNT);
    }

    function test_Revert_RefundAfterRejection_SecondCallOnRefunded() public {
        _toRejected(id, 0);
        vm.warp(_ms(id, 0).rejectedAt + 7 days);
        vm.prank(client);
        escrow.refundAfterRejection(id, 0);
        _assertState(id, 0, REFUNDED);

        vm.warp(block.timestamp + 100 days);
        vm.prank(client);
        vm.expectRevert(_badState(REFUNDED));
        escrow.refundAfterRejection(id, 0);

        assertEq(_claim(client), AMOUNT);
        FreelanceEscrow.JobView memory j = escrow.getJob(id);
        assertEq(j.refunded, AMOUNT);
        assertEq(j.remaining, AMOUNT);
        assertEq(escrow.totalClaimable(), AMOUNT);
    }

    function test_Revert_CrossRefund_OnAlreadyRefundedMilestone() public {
        // refunded via the 7-day path, then tried via the deadline path
        _toRejected(id, 0);
        vm.warp(_ms(id, 0).rejectedAt + 7 days);
        vm.prank(client);
        escrow.refundAfterRejection(id, 0);
        vm.prank(client);
        vm.expectRevert(_badState(REFUNDED));
        escrow.refundMilestone(id, 0);

        // refunded via the deadline path, then tried via the 7-day path
        _start(id, 1);
        vm.warp(_ms(id, 1).deadline + 1);
        _refundM(id, 1);
        vm.prank(client);
        vm.expectRevert(_badState(REFUNDED));
        escrow.refundAfterRejection(id, 1);

        assertEq(_claim(client), 2 * AMOUNT);
    }

    function test_Revert_DeclineJob_NotFound() public {
        vm.prank(freelancer);
        vm.expectRevert(abi.encodeWithSelector(FreelanceEscrow.JobNotFound.selector, 7));
        escrow.declineJob(7);
    }
}
