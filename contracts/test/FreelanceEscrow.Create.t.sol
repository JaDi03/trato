// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FreelanceEscrow} from "../FreelanceEscrow.sol";
import {FreelanceEscrowTestBase} from "./FreelanceEscrow.Base.t.sol";
import {FeeUSDC} from "./mocks/TestTokens.sol";

/// @notice createJob validation, percentage/rounding behaviour, and conservation fuzzing.
contract FreelanceEscrowCreateTest is FreelanceEscrowTestBase {
    FreelanceEscrow.MilestoneInput[] internal scratch;

    // ------------------------------------------------------------ constructor / happy

    function test_Constructor_RevertsOnZeroAndNonContractToken() public {
        vm.expectRevert(FreelanceEscrow.ZeroAddress.selector);
        new FreelanceEscrow(address(0));
        vm.expectRevert(FreelanceEscrow.InvalidToken.selector);
        new FreelanceEscrow(stranger);
    }

    function test_CreateJob_StoresJobAndPullsFunds() public {
        uint256 before_ = usdc.balanceOf(client);
        uint256 id = _createN(TOTAL, 2);
        assertEq(id, 1);
        FreelanceEscrow.JobView memory j = escrow.getJob(id);
        assertEq(j.client, client);
        assertEq(j.freelancer, freelancer);
        assertEq(j.arbiter, arbiter);
        assertEq(j.total, TOTAL);
        assertEq(j.remaining, TOTAL);
        assertEq(j.milestoneCount, 2);
        assertEq(usdc.balanceOf(address(escrow)), TOTAL);
        assertEq(before_ - usdc.balanceOf(client), TOTAL);
        assertEq(escrow.totalRemaining(), TOTAL);
        assertEq(_ms(id, 0).unlockedAt, block.timestamp);
        assertEq(_ms(id, 1).unlockedAt, 0);
        uint256[] memory js = escrow.jobsOf(p1);
        assertEq(js.length, 1);
    }

    function test_CreateJob_TwentyMilestonesAndTenPayeesAllowed() public {
        FreelanceEscrow.MilestoneInput[] memory ms = new FreelanceEscrow.MilestoneInput[](20);
        address[] memory ps = new address[](10);
        uint16[] memory sh = new uint16[](10);
        for (uint256 i; i < 10; ++i) {
            ps[i] = address(uint160(0x5000 + i));
            sh[i] = 1000;
        }
        for (uint256 i; i < 20; ++i) {
            ms[i] = _inputWith(500, ps, sh, 0);
        }
        uint256 id = _create(TOTAL, ms);
        assertEq(escrow.getJob(id).milestoneCount, 20);
    }

    function test_CreateJob_FreelancerOrClientMayBePayee() public {
        address[] memory ps = new address[](2);
        ps[0] = freelancer;
        ps[1] = client;
        uint16[] memory sh = new uint16[](2);
        sh[0] = 5000;
        sh[1] = 5000;
        FreelanceEscrow.MilestoneInput[] memory ms = new FreelanceEscrow.MilestoneInput[](1);
        ms[0] = _inputWith(10_000, ps, sh, 0);
        uint256 id = _create(TOTAL, ms);
        assertEq(escrow.getJob(id).milestoneCount, 1);
    }

    // ------------------------------------------------------------ reverts: bps

    function test_Revert_BpsSumBelow10000() public {
        FreelanceEscrow.MilestoneInput[] memory ms = new FreelanceEscrow.MilestoneInput[](2);
        ms[0] = _input(5000);
        ms[1] = _input(4000);
        _createRevert(_sel(FreelanceEscrow.InvalidBasisPoints.selector), TOTAL, ms);
    }

    function test_Revert_BpsSumAbove10000() public {
        FreelanceEscrow.MilestoneInput[] memory ms = new FreelanceEscrow.MilestoneInput[](2);
        ms[0] = _input(6000);
        ms[1] = _input(6000);
        _createRevert(_sel(FreelanceEscrow.InvalidBasisPoints.selector), TOTAL, ms);
    }

    function test_Revert_ZeroBps() public {
        FreelanceEscrow.MilestoneInput[] memory ms = new FreelanceEscrow.MilestoneInput[](2);
        ms[0] = _input(0);
        ms[1] = _input(10_000);
        _createRevert(_sel(FreelanceEscrow.InvalidBasisPoints.selector), TOTAL, ms);
    }

    // ------------------------------------------------------------ reverts: payees / shares

    function test_Revert_PayeeSharesDoNotSumTo10000() public {
        FreelanceEscrow.MilestoneInput[] memory ms = _evenInputs(1, 0);
        ms[0].shares[1] = 2000; // 7000 + 2000
        _createRevert(_sel(FreelanceEscrow.InvalidShares.selector), TOTAL, ms);
        ms[0].shares[1] = 3001; // 10001
        _createRevert(_sel(FreelanceEscrow.InvalidShares.selector), TOTAL, ms);
    }

    function test_Revert_SharesInSecondMilestoneChecked() public {
        FreelanceEscrow.MilestoneInput[] memory ms = _evenInputs(2, 0);
        ms[1].shares[0] = 6999;
        _createRevert(_sel(FreelanceEscrow.InvalidShares.selector), TOTAL, ms);
    }

    function test_Revert_ZeroShareOrLengthMismatch() public {
        FreelanceEscrow.MilestoneInput[] memory ms = _evenInputs(1, 0);
        ms[0].shares[0] = 0;
        ms[0].shares[1] = 10_000;
        _createRevert(_sel(FreelanceEscrow.InvalidShares.selector), TOTAL, ms);

        ms = _evenInputs(1, 0);
        ms[0].shares = new uint16[](1);
        ms[0].shares[0] = 10_000;
        _createRevert(_sel(FreelanceEscrow.InvalidShares.selector), TOTAL, ms);
    }

    function test_Revert_DuplicatePayee() public {
        FreelanceEscrow.MilestoneInput[] memory ms = _evenInputs(1, 0);
        ms[0].payees[1] = p1;
        _createRevert(abi.encodeWithSelector(FreelanceEscrow.DuplicatePayee.selector, p1), TOTAL, ms);
    }

    function test_Revert_ZeroAddressPayee() public {
        FreelanceEscrow.MilestoneInput[] memory ms = _evenInputs(1, 0);
        ms[0].payees[0] = address(0);
        _createRevert(_sel(FreelanceEscrow.ZeroAddress.selector), TOTAL, ms);
    }

    function test_Revert_ZeroPayees() public {
        FreelanceEscrow.MilestoneInput[] memory ms = _evenInputs(1, 0);
        ms[0].payees = new address[](0);
        ms[0].shares = new uint16[](0);
        _createRevert(_sel(FreelanceEscrow.InvalidPayeeCount.selector), TOTAL, ms);
    }

    function test_Revert_MoreThanTenPayees() public {
        FreelanceEscrow.MilestoneInput[] memory ms = _evenInputs(1, 0);
        address[] memory ps = new address[](11);
        uint16[] memory sh = new uint16[](11);
        for (uint256 i; i < 11; ++i) {
            ps[i] = address(uint160(0x6000 + i));
            sh[i] = i == 10 ? 1000 : 900; // even a valid-sum list must be rejected by count
        }
        sh[10] = uint16(10_000 - 900 * 10);
        ms[0].payees = ps;
        ms[0].shares = sh;
        _createRevert(_sel(FreelanceEscrow.InvalidPayeeCount.selector), TOTAL, ms);
    }

    function test_Revert_ZeroDurations() public {
        FreelanceEscrow.MilestoneInput[] memory ms = _evenInputs(1, 0);
        ms[0].deliveryDuration = 0;
        _createRevert(_sel(FreelanceEscrow.InvalidDuration.selector), TOTAL, ms);
        ms[0].deliveryDuration = DELIVERY;
        ms[0].reviewPeriod = 0;
        _createRevert(_sel(FreelanceEscrow.InvalidDuration.selector), TOTAL, ms);
    }

    // ------------------------------------------------------------ reverts: roles / counts / total

    function test_Revert_ZeroFreelancerOrArbiter() public {
        FreelanceEscrow.MilestoneInput[] memory ms = _evenInputs(1, 0);
        vm.startPrank(client);
        vm.expectRevert(FreelanceEscrow.ZeroAddress.selector);
        escrow.createJob(address(0), arbiter, TOTAL, ms);
        vm.expectRevert(FreelanceEscrow.ZeroAddress.selector);
        escrow.createJob(freelancer, address(0), TOTAL, ms);
        vm.stopPrank();
    }

    function test_Revert_ArbiterOrFreelancerRoleClashes() public {
        FreelanceEscrow.MilestoneInput[] memory ms = _evenInputs(1, 0);
        vm.startPrank(client);
        vm.expectRevert(FreelanceEscrow.InvalidRoles.selector);
        escrow.createJob(freelancer, client, TOTAL, ms); // arbiter == client
        vm.expectRevert(FreelanceEscrow.InvalidRoles.selector);
        escrow.createJob(freelancer, freelancer, TOTAL, ms); // arbiter == freelancer
        vm.expectRevert(FreelanceEscrow.InvalidRoles.selector);
        escrow.createJob(client, arbiter, TOTAL, ms); // freelancer == client
        vm.stopPrank();
    }

    function test_Revert_ArbiterEqualsPayee() public {
        FreelanceEscrow.MilestoneInput[] memory ms = _evenInputs(2, 0);
        ms[1].payees[0] = arbiter;
        _createRevert(_sel(FreelanceEscrow.InvalidRoles.selector), TOTAL, ms);
    }

    function test_Revert_MilestoneCountZeroOrAbove20() public {
        _createRevert(
            _sel(FreelanceEscrow.InvalidMilestoneCount.selector), TOTAL, new FreelanceEscrow.MilestoneInput[](0)
        );
        FreelanceEscrow.MilestoneInput[] memory ms = new FreelanceEscrow.MilestoneInput[](21);
        for (uint256 i; i < 21; ++i) {
            ms[i] = _input(i == 20 ? 9524 : 1);
        }
        _createRevert(_sel(FreelanceEscrow.InvalidMilestoneCount.selector), TOTAL, ms);
    }

    function test_Revert_TotalZero() public {
        _createRevert(_sel(FreelanceEscrow.InvalidTotal.selector), 0, _evenInputs(1, 0));
    }

    function test_Revert_Unfunded_NoAllowance() public {
        FreelanceEscrow.MilestoneInput[] memory ms = _evenInputs(1, 0);
        vm.prank(client);
        vm.expectRevert(); // ERC20InsufficientAllowance bubbles through SafeERC20
        escrow.createJob(freelancer, arbiter, TOTAL, ms);
    }

    function test_Revert_FundingMismatch_FeeOnTransferToken() public {
        FeeUSDC fee = new FeeUSDC();
        FreelanceEscrow e2 = new FreelanceEscrow(address(fee));
        fee.mint(client, TOTAL);
        FreelanceEscrow.MilestoneInput[] memory ms = _evenInputs(1, 0);
        vm.startPrank(client);
        fee.approve(address(e2), TOTAL);
        vm.expectRevert(abi.encodeWithSelector(FreelanceEscrow.FundingMismatch.selector, TOTAL, TOTAL - 1));
        e2.createJob(freelancer, arbiter, TOTAL, ms);
        vm.stopPrank();
    }

    // ------------------------------------------------------------ rounding

    function test_Rounding_LastMilestoneTakesRemainder() public {
        FreelanceEscrow.MilestoneInput[] memory ms = new FreelanceEscrow.MilestoneInput[](3);
        ms[0] = _input(3333);
        ms[1] = _input(3333);
        ms[2] = _input(3334);
        uint256 id = _create(1_000_003, ms);
        assertEq(_ms(id, 0).amount, 333_300);
        assertEq(_ms(id, 1).amount, 333_300);
        assertEq(_ms(id, 2).amount, 333_403);
        assertEq(_ms(id, 0).amount + _ms(id, 1).amount + _ms(id, 2).amount, 1_000_003);
    }

    function test_Rounding_LastPayeeTakesRemainder() public {
        address[] memory ps = new address[](3);
        ps[0] = p1;
        ps[1] = p2;
        ps[2] = p3;
        uint16[] memory sh = new uint16[](3);
        sh[0] = 3333;
        sh[1] = 3333;
        sh[2] = 3334;
        FreelanceEscrow.MilestoneInput[] memory ms = new FreelanceEscrow.MilestoneInput[](1);
        ms[0] = _inputWith(10_000, ps, sh, 0);
        uint256 id = _create(1_000_003, ms);
        _toDelivered(id, 0);
        _approveM(id, 0);
        assertEq(_claim(p1), 333_300);
        assertEq(_claim(p2), 333_300);
        assertEq(_claim(p3), 333_403);
        assertEq(_claim(p1) + _claim(p2) + _claim(p3), 1_000_003);
        uint256[] memory exp = _split(1_000_003, sh);
        assertEq(_claim(p3), exp[2]);
    }

    function test_Rounding_ZeroValueMilestoneStillCompletes() public {
        // total 1 across 5000/5000 => amounts 0 and 1
        uint256 id = _createN(1, 2);
        assertEq(_ms(id, 0).amount, 0);
        assertEq(_ms(id, 1).amount, 1);
        _toDelivered(id, 0);
        _approveM(id, 0);
        _assertState(id, 0, PAID);
        _toDelivered(id, 1);
        _approveM(id, 1);
        assertTrue(escrow.getJob(id).completed);
        assertEq(_claim(p1) + _claim(p2), 1);
        assertEq(_claim(p2), 1); // last payee takes the remainder unit
    }

    // ------------------------------------------------------------ fuzz

    function testFuzz_Split_ResolveDisputeExact(uint256 total, uint256 refund) public {
        total = bound(total, 1, 1e12);
        refund = bound(refund, 0, total);
        address[] memory ps = new address[](3);
        ps[0] = p1;
        ps[1] = p2;
        ps[2] = p3;
        uint16[] memory sh = new uint16[](3);
        sh[0] = 3333;
        sh[1] = 3333;
        sh[2] = 3334;
        FreelanceEscrow.MilestoneInput[] memory ms = new FreelanceEscrow.MilestoneInput[](1);
        ms[0] = _inputWith(10_000, ps, sh, 0);
        uint256 id = _create(total, ms);
        _toDisputed(id, 0);
        _resolve(id, 0, refund);
        assertEq(_claim(client), refund);
        assertEq(_claim(p1) + _claim(p2) + _claim(p3), total - refund);
        uint256[] memory exp = _split(total - refund, sh);
        assertEq(_claim(p1), exp[0]);
        assertEq(_claim(p3), exp[2]);
        assertEq(escrow.totalClaimable(), total);
        assertEq(escrow.totalRemaining(), 0);
    }

    function testFuzz_FullSettlementConservesFunds(uint256 total, uint256 seed) public {
        total = bound(total, 1, 1e12);
        uint256 n = 1 + (_h(seed, "n", 0) % 20);
        uint256 id = _create(total, _randomInputs(seed, n));

        for (uint256 m; m < n; ++m) {
            _settleRandom(id, m, seed);
            FreelanceEscrow.JobView memory j = escrow.getJob(id);
            assertEq(j.paid + j.refunded + j.remaining, total, "paid+refunded+remaining");
            assertEq(escrow.totalRemaining(), j.remaining);
            assertEq(escrow.totalClaimable(), j.paid + j.refunded);
        }

        FreelanceEscrow.JobView memory f = escrow.getJob(id);
        assertTrue(f.completed);
        assertEq(f.remaining, 0);
        assertEq(f.paid + f.refunded, total);
        assertEq(_sumClaimable(), total, "sum of claimable == deposited");
        assertEq(escrow.totalClaimable(), total);
        assertEq(usdc.balanceOf(address(escrow)), total);

        _withdrawAll();
        assertEq(usdc.balanceOf(address(escrow)), 0);
        assertEq(escrow.totalClaimable(), 0);
    }

    // ------------------------------------------------------------ fuzz helpers

    function _h(uint256 seed, string memory tag, uint256 i) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(seed, tag, i)));
    }

    function _randomInputs(uint256 seed, uint256 n) internal view returns (FreelanceEscrow.MilestoneInput[] memory ms) {
        ms = new FreelanceEscrow.MilestoneInput[](n);
        uint256 remaining = 10_000;
        for (uint256 i; i < n; ++i) {
            uint256 bps = remaining;
            if (i + 1 != n) bps = 1 + (_h(seed, "bps", i) % (remaining - (n - 1 - i)));
            remaining -= bps;
            (address[] memory ps, uint16[] memory sh) = _randomPayees(seed, i);
            ms[i] = _inputWith(uint16(bps), ps, sh, REVISIONS);
        }
    }

    function _randomPayees(uint256 seed, uint256 i) internal pure returns (address[] memory ps, uint16[] memory sh) {
        uint256 k = 1 + (_h(seed, "k", i) % 10);
        ps = new address[](k);
        sh = new uint16[](k);
        uint256 remaining = 10_000;
        for (uint256 j; j < k; ++j) {
            ps[j] = address(uint160(0xA000 + ((i * 3 + j) % 15)));
            uint256 s = remaining;
            if (j + 1 != k) s = 1 + (_h(seed, "sh", i * 100 + j) % (remaining - (k - 1 - j)));
            remaining -= s;
            sh[j] = uint16(s);
        }
    }

    function _settleRandom(uint256 id, uint256 m, uint256 seed) internal {
        uint256 mode = _h(seed, "mode", m) % 4;
        _start(id, m);
        if (mode == 2) {
            vm.warp(_ms(id, m).deadline + 1);
            _refundM(id, m);
            return;
        }
        _deliver(id, m);
        if (mode == 0) {
            _approveM(id, m);
        } else if (mode == 1) {
            _clientDispute(id, m);
            _resolve(id, m, _h(seed, "refund", m) % (_ms(id, m).amount + 1));
        } else {
            vm.warp(block.timestamp + REVIEW);
            vm.prank(stranger);
            escrow.autoApprove(id, m);
        }
    }

    function _sumClaimable() internal view returns (uint256 sum) {
        sum = _claim(client);
        for (uint256 i; i < 15; ++i) {
            sum += _claim(address(uint160(0xA000 + i)));
        }
    }

    function _withdrawAll() internal {
        address[16] memory who;
        who[0] = client;
        for (uint256 i; i < 15; ++i) {
            who[i + 1] = address(uint160(0xA000 + i));
        }
        for (uint256 i; i < 16; ++i) {
            if (_claim(who[i]) > 0) {
                vm.prank(who[i]);
                escrow.withdraw();
            }
        }
    }
}
