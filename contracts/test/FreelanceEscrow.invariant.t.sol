// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {FreelanceEscrow} from "../FreelanceEscrow.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

/// @dev Bounded random-action driver. Not a Test: it only exposes the escrow actions as fuzz targets.
///      Actors are fixed: 2 clients, 2 freelancers, 2 arbiters, 4 payees. Up to MAX_JOBS jobs.
contract EscrowHandler {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    FreelanceEscrow public immutable escrow;
    MockUSDC public immutable usdc;

    address[] internal _clients;
    address[] internal _freelancers;
    address[] internal _arbiters;
    address[] internal _payees;
    uint256[] internal _jobIds;
    mapping(string => uint256) public hits;

    uint256 internal constant MAX_JOBS = 8;

    constructor(FreelanceEscrow e, MockUSDC u) {
        escrow = e;
        usdc = u;
        for (uint256 i; i < 2; ++i) {
            _clients.push(address(uint160(0x1001 + i)));
            _freelancers.push(address(uint160(0x2001 + i)));
            _arbiters.push(address(uint160(0x3001 + i)));
        }
        for (uint256 i; i < 4; ++i) {
            _payees.push(address(uint160(0x4001 + i)));
        }
    }

    // ------------------------------------------------------------ views for the invariants

    function jobIds() external view returns (uint256[] memory) {
        return _jobIds;
    }

    /// @dev Every address that can ever be credited.
    function actors() external view returns (address[] memory all) {
        all = new address[](10);
        for (uint256 i; i < 2; ++i) {
            all[i] = _clients[i];
            all[2 + i] = _freelancers[i];
            all[4 + i] = _arbiters[i];
        }
        for (uint256 i; i < 4; ++i) {
            all[6 + i] = _payees[i];
        }
    }

    // ------------------------------------------------------------ helpers

    function _b(uint256 x, uint256 lo, uint256 hi) internal pure returns (uint256) {
        if (hi <= lo) return lo;
        return lo + (x % (hi - lo + 1));
    }

    function _terminal(FreelanceEscrow.MilestoneState s) internal pure returns (bool) {
        return s == FreelanceEscrow.MilestoneState.Paid || s == FreelanceEscrow.MilestoneState.Refunded;
    }

    /// @dev Half of the time target the first non-terminal milestone so sequences make progress.
    function _pick(uint256 js, uint256 mseed)
        internal
        returns (uint256 id, uint256 m, FreelanceEscrow.JobView memory j)
    {
        if (_jobIds.length == 0) return (0, 0, j);
        if ((mseed >> 4) % 3 == 0) vm.warp(block.timestamp + _b(mseed >> 8, 0, 4 days));
        id = _jobIds[js % _jobIds.length];
        j = escrow.getJob(id);
        m = mseed % j.milestoneCount;
        if (mseed % 2 == 0) {
            for (uint256 i; i < j.milestoneCount; ++i) {
                if (!_terminal(escrow.getMilestone(id, i).state)) {
                    m = i;
                    break;
                }
            }
        }
    }

    function _inputs(uint256 s, uint256 n) internal view returns (FreelanceEscrow.MilestoneInput[] memory ms) {
        ms = new FreelanceEscrow.MilestoneInput[](n);
        uint256 acc;
        for (uint256 i; i < n; ++i) {
            uint256 bps = i + 1 == n ? 10_000 - acc : 10_000 / n;
            acc += bps;
            ms[i] = _milestone(s >> (i * 12), uint16(bps));
        }
    }

    function _milestone(uint256 s, uint16 bps) internal view returns (FreelanceEscrow.MilestoneInput memory mi) {
        uint256 k = _b(s, 1, 4);
        uint256 first = (s >> 3) % 4;
        mi.bps = bps;
        mi.payees = new address[](k);
        mi.shares = new uint16[](k);
        for (uint256 j; j < k; ++j) {
            mi.payees[j] = _payees[(first + j) % 4];
            mi.shares[j] = j + 1 == k ? uint16(10_000 - (10_000 / k) * (k - 1)) : uint16(10_000 / k);
        }
        mi.deliveryDuration = uint32(_b(s >> 5, 1 days, 10 days));
        mi.reviewPeriod = uint32(_b(s >> 8, 1 days, 5 days));
        mi.maxRevisions = uint8(_b(s >> 10, 0, 2));
    }

    // ------------------------------------------------------------ actions

    function createJob(uint256 seed) external {
        if (_jobIds.length >= MAX_JOBS) return;
        address c = _clients[seed % 2];
        address f = _freelancers[(seed >> 8) % 2];
        address a = _arbiters[(seed >> 16) % 2];
        uint256 total = _b(seed >> 24, 1, 1e9);
        FreelanceEscrow.MilestoneInput[] memory ms = _inputs(seed >> 64, _b(seed >> 56, 1, 5));
        usdc.mint(c, total);
        vm.prank(c);
        usdc.approve(address(escrow), total);
        vm.prank(c);
        _jobIds.push(escrow.createJob(f, a, total, ms));
        hits["createJob"]++;
    }

    function start(uint256 js, uint256 ms) external {
        (uint256 id, uint256 m, FreelanceEscrow.JobView memory j) = _pick(js, ms);
        if (id == 0) return;
        vm.prank(j.freelancer);
        try escrow.startMilestone(id, m) {
            hits["start"]++;
        } catch {}
    }

    function deliver(uint256 js, uint256 ms) external {
        (uint256 id, uint256 m, FreelanceEscrow.JobView memory j) = _pick(js, ms);
        if (id == 0) return;
        vm.prank(j.freelancer);
        try escrow.deliver(id, m) {
            hits["deliver"]++;
        } catch {}
    }

    function approve(uint256 js, uint256 ms) external {
        (uint256 id, uint256 m, FreelanceEscrow.JobView memory j) = _pick(js, ms);
        if (id == 0) return;
        vm.prank(j.client);
        try escrow.approve(id, m) {
            hits["approve"]++;
        } catch {}
    }

    function proposePartial(uint256 js, uint256 ms, uint256 refundSeed) external {
        (uint256 id, uint256 m, FreelanceEscrow.JobView memory j) = _pick(js, ms);
        if (id == 0) return;
        uint256 amount = escrow.getMilestone(id, m).amount;
        // Bounded to the valid open interval [1, amount - 1]; amount <= 1 yields an (expected) InvalidRefund revert.
        uint256 refund = amount > 1 ? _b(refundSeed, 1, amount - 1) : 1;
        vm.prank(j.client);
        try escrow.proposePartial(id, m, refund) {
            hits["proposePartial"]++;
        } catch {}
    }

    function acceptPartial(uint256 js, uint256 ms) external {
        (uint256 id, uint256 m, FreelanceEscrow.JobView memory j) = _pick(js, ms);
        if (id == 0) return;
        uint256 expected = escrow.getMilestone(id, m).proposedRefund;
        vm.prank(j.freelancer);
        try escrow.acceptPartial(id, m, expected) {
            hits["acceptPartial"]++;
        } catch {}
    }

    function autoApprove(uint256 js, uint256 ms, uint256 callerSeed) external {
        (uint256 id, uint256 m,) = _pick(js, ms);
        if (id == 0) return;
        vm.warp(block.timestamp + _b(callerSeed >> 8, 0, 5 days));
        vm.prank(_payees[callerSeed % 4]);
        try escrow.autoApprove(id, m) {
            hits["autoApprove"]++;
        } catch {}
    }

    function requestRevision(uint256 js, uint256 ms) external {
        (uint256 id, uint256 m, FreelanceEscrow.JobView memory j) = _pick(js, ms);
        if (id == 0) return;
        vm.prank(j.client);
        try escrow.requestRevision(id, m) {
            hits["revise"]++;
        } catch {}
    }

    function rejectDelivery(uint256 js, uint256 ms) external {
        (uint256 id, uint256 m, FreelanceEscrow.JobView memory j) = _pick(js, ms);
        if (id == 0) return;
        vm.prank(j.client);
        try escrow.rejectDelivery(id, m) {
            hits["reject"]++;
        } catch {}
    }

    function openDispute(uint256 js, uint256 ms, bool byFreelancer) external {
        (uint256 id, uint256 m, FreelanceEscrow.JobView memory j) = _pick(js, ms);
        if (id == 0) return;
        vm.prank(byFreelancer ? j.freelancer : j.client);
        try escrow.openDispute(id, m) {
            hits["dispute"]++;
        } catch {}
    }

    function resolveDispute(uint256 js, uint256 ms, uint256 refundSeed) external {
        (uint256 id, uint256 m, FreelanceEscrow.JobView memory j) = _pick(js, ms);
        if (id == 0) return;
        uint256 refund = _b(refundSeed, 0, escrow.getMilestone(id, m).amount);
        vm.prank(j.arbiter);
        try escrow.resolveDispute(id, m, refund) {
            hits["resolve"]++;
        } catch {}
    }

    function resolveDisputeByTimeout(uint256 js, uint256 ms, uint256 jump) external {
        (uint256 id, uint256 m,) = _pick(js, ms);
        if (id == 0) return;
        vm.warp(block.timestamp + _b(jump, 0, 31 days));
        try escrow.resolveDisputeByTimeout(id, m) {
            hits["timeout"]++;
        } catch {}
    }

    function refundMilestone(uint256 js, uint256 ms, uint256 jump) external {
        (uint256 id, uint256 m, FreelanceEscrow.JobView memory j) = _pick(js, ms);
        if (id == 0) return;
        vm.warp(block.timestamp + _b(jump, 0, 15 days));
        vm.prank(j.client);
        try escrow.refundMilestone(id, m) {
            hits["refund"]++;
        } catch {}
    }

    function refundAfterRejection(uint256 js, uint256 ms, uint256 jump) external {
        (uint256 id, uint256 m, FreelanceEscrow.JobView memory j) = _pick(js, ms);
        if (id == 0) return;
        vm.warp(block.timestamp + _b(jump, 0, 8 days));
        vm.prank(j.client);
        try escrow.refundAfterRejection(id, m) {
            hits["refundRejected"]++;
        } catch {}
    }

    function declineJob(uint256 js) external {
        if (js % 12 != 0) return; // keep declines rare so jobs progress
        (uint256 id,, FreelanceEscrow.JobView memory j) = _pick(js >> 2, 1);
        if (id == 0) return;
        vm.prank(j.freelancer);
        try escrow.declineJob(id) {
            hits["decline"]++;
        } catch {}
    }

    function withdraw(uint256 actorSeed) external {
        address[] memory all = this.actors();
        address who = all[actorSeed % 10];
        for (uint256 i; i < 10; ++i) {
            address cand = all[(actorSeed + i) % 10];
            if (escrow.claimable(cand) > 0) {
                who = cand;
                break;
            }
        }
        vm.prank(who);
        try escrow.withdraw() {
            hits["withdraw"]++;
        } catch {}
    }

    function _call(address who, bytes memory data, string memory tag) internal returns (bool ok) {
        vm.prank(who);
        (ok,) = address(escrow).call(data);
        if (ok) hits[tag]++;
    }

    function _rejectLoop(uint256 id, uint256 m, FreelanceEscrow.JobView memory j) internal returns (bool) {
        for (uint256 k; k < 3; ++k) {
            if (_call(j.client, abi.encodeCall(escrow.rejectDelivery, (id, m)), "reject")) return true;
            _call(j.client, abi.encodeCall(escrow.requestRevision, (id, m)), "revise");
            _call(j.freelancer, abi.encodeCall(escrow.deliver, (id, m)), "deliver");
        }
        return false;
    }

    /// @dev Composite happy-ish path on the first open milestone so deep states are reached often.
    function flow(uint256 js, uint256 seed) external {
        (uint256 id, uint256 m, FreelanceEscrow.JobView memory j) = _pick(js, 0);
        if (id == 0) return;
        _call(j.freelancer, abi.encodeCall(escrow.startMilestone, (id, m)), "start");
        _call(j.freelancer, abi.encodeCall(escrow.deliver, (id, m)), "deliver");
        uint256 branch = seed % 6;
        if (branch == 0) {
            uint256 amt = escrow.getMilestone(id, m).amount;
            if ((seed >> 16) % 2 == 0 && amt > 1) {
                uint256 refund = _b(seed >> 24, 1, amt - 1);
                _call(j.client, abi.encodeCall(escrow.proposePartial, (id, m, refund)), "proposePartial");
                _call(j.freelancer, abi.encodeCall(escrow.acceptPartial, (id, m, refund)), "acceptPartial");
            } else {
                _call(j.client, abi.encodeCall(escrow.approve, (id, m)), "approve");
            }
        } else if (branch == 1) {
            _call(j.client, abi.encodeCall(escrow.requestRevision, (id, m)), "revise");
            _call(j.freelancer, abi.encodeCall(escrow.deliver, (id, m)), "deliver");
        } else if (branch == 2) {
            if (_call(j.client, abi.encodeCall(escrow.openDispute, (id, m)), "dispute")) {
                uint256 refund = _b(seed >> 8, 0, escrow.getMilestone(id, m).amount);
                _call(j.arbiter, abi.encodeCall(escrow.resolveDispute, (id, m, refund)), "resolve");
            }
        } else if (branch == 3) {
            if (_rejectLoop(id, m, j)) {
                _call(j.freelancer, abi.encodeCall(escrow.openDispute, (id, m)), "dispute");
            }
        } else if (branch == 4) {
            _rejectLoop(id, m, j);
        } else {
            _call(j.client, abi.encodeCall(escrow.openDispute, (id, m)), "dispute");
        }
    }

    function warp(uint256 d) external {
        vm.warp(block.timestamp + _b(d, 0, d % 4 == 0 ? 40 days : 8 days));
    }
}

/// @dev Shared deployment + handler wiring for both invariant contracts.
abstract contract EscrowInvariantSetup is Test {
    FreelanceEscrow internal escrow;
    MockUSDC internal usdc;
    EscrowHandler internal handler;

    function setUp() public virtual {
        vm.warp(1_700_000_000);
        usdc = new MockUSDC();
        escrow = new FreelanceEscrow(address(usdc));
        handler = new EscrowHandler(escrow, usdc);
        targetContract(address(handler));
    }

    function afterInvariant() public view {
        console2.log("createJob", handler.hits("createJob"));
        console2.log("start", handler.hits("start"));
        console2.log("deliver", handler.hits("deliver"));
        console2.log("approve", handler.hits("approve"));
        console2.log("proposePartial", handler.hits("proposePartial"));
        console2.log("acceptPartial", handler.hits("acceptPartial"));
        console2.log("autoApprove", handler.hits("autoApprove"));
        console2.log("revise", handler.hits("revise"));
        console2.log("reject", handler.hits("reject"));
        console2.log("dispute", handler.hits("dispute"));
        console2.log("resolve", handler.hits("resolve"));
        console2.log("timeout", handler.hits("timeout"));
        console2.log("refund", handler.hits("refund"));
        console2.log("refundRejected", handler.hits("refundRejected"));
        console2.log("decline", handler.hits("decline"));
        console2.log("withdraw", handler.hits("withdraw"));
    }

    function _isTerminal(FreelanceEscrow.MilestoneState s) internal pure returns (bool) {
        return s == FreelanceEscrow.MilestoneState.Paid || s == FreelanceEscrow.MilestoneState.Refunded;
    }
}

/// forge-config: default.invariant.runs = 100
/// forge-config: default.invariant.depth = 300
/// forge-config: default.invariant.fail_on_revert = false
contract FreelanceEscrowJobInvariantTest is EscrowInvariantSetup {
    /// deposited == paid + refunded + remaining, for every job, at all times.
    function invariant_PerJob_DepositedEqualsPaidPlusRefundedPlusRemaining() public view {
        uint256[] memory ids = handler.jobIds();
        for (uint256 i; i < ids.length; ++i) {
            FreelanceEscrow.JobView memory j = escrow.getJob(ids[i]);
            assertEq(j.total, j.paid + j.refunded + j.remaining, "job accounting identity");
        }
    }

    /// remaining == Σ amount of non-terminal milestones; paid+refunded == Σ amount of terminal ones.
    function invariant_PerJob_RemainingEqualsOpenMilestoneAmounts() public view {
        uint256[] memory ids = handler.jobIds();
        for (uint256 i; i < ids.length; ++i) {
            FreelanceEscrow.JobView memory j = escrow.getJob(ids[i]);
            uint256 open;
            uint256 closed;
            for (uint256 m; m < j.milestoneCount; ++m) {
                FreelanceEscrow.Milestone memory ms = escrow.getMilestone(ids[i], m);
                if (_isTerminal(ms.state)) closed += ms.amount;
                else open += ms.amount;
            }
            assertEq(j.remaining, open, "remaining == open milestone amounts");
            assertEq(j.paid + j.refunded, closed, "paid+refunded == closed milestone amounts");
            assertEq(open + closed, j.total, "milestone amounts sum to deposit");
        }
    }

    /// Per-milestone state/field consistency and sequential gating.
    function invariant_PerMilestone_StateConsistency() public view {
        uint256[] memory ids = handler.jobIds();
        for (uint256 i; i < ids.length; ++i) {
            FreelanceEscrow.JobView memory j = escrow.getJob(ids[i]);
            uint256 bpsSum;
            bool allTerminal = true;
            FreelanceEscrow.MilestoneState prev = FreelanceEscrow.MilestoneState.Paid;
            for (uint256 m; m < j.milestoneCount; ++m) {
                FreelanceEscrow.Milestone memory ms = escrow.getMilestone(ids[i], m);
                bpsSum += ms.bps;
                if (!_isTerminal(ms.state)) allTerminal = false;
                _checkMilestone(ms, prev);
                prev = ms.state;
            }
            assertEq(bpsSum, 10_000, "bps sum");
            assertEq(j.completed, allTerminal, "completed iff all milestones terminal");
        }
    }

    function _checkMilestone(FreelanceEscrow.Milestone memory ms, FreelanceEscrow.MilestoneState prev) internal pure {
        FreelanceEscrow.MilestoneState s = ms.state;
        assertTrue(s != FreelanceEscrow.MilestoneState.Approved, "Approved is transient");
        assertLe(ms.revisionsUsed, ms.maxRevisions, "revisions within limit");
        if (ms.rejectedFinal) {
            assertEq(ms.revisionsUsed, ms.maxRevisions, "final rejection only after revisions exhausted");
            assertGt(ms.rejectedAt, 0, "rejectedAt set");
        }
        if (s == FreelanceEscrow.MilestoneState.Pending) {
            assertEq(ms.startedAt, 0, "pending => not started");
            assertEq(ms.deliveredAt, 0, "pending => not delivered");
            assertEq(ms.revisionsUsed, 0, "pending => no revisions");
            assertFalse(ms.rejectedFinal, "pending => not rejected");
        } else {
            assertGt(ms.unlockedAt, 0, "non-pending milestone was unlocked");
            // previous milestone must be settled or disputed once this one has left Pending
            assertTrue(
                prev == FreelanceEscrow.MilestoneState.Paid || prev == FreelanceEscrow.MilestoneState.Refunded
                    || prev == FreelanceEscrow.MilestoneState.Disputed,
                "sequential gating"
            );
        }
        if (ms.proposedRefund != 0) {
            assertTrue(s == FreelanceEscrow.MilestoneState.Delivered, "proposal only visible while Delivered");
            assertLt(ms.proposedRefund, ms.amount, "proposal strictly below amount");
        }
        if (s == FreelanceEscrow.MilestoneState.Delivered) assertGt(ms.deliveredAt, 0, "delivered => deliveredAt");
        if (s == FreelanceEscrow.MilestoneState.InRevision) assertGt(ms.revisionsUsed, 0, "in revision => used >= 1");
        if (s == FreelanceEscrow.MilestoneState.Disputed) {
            assertGt(ms.disputedAt, 0, "disputed => disputedAt");
            assertGt(ms.deliveredAt, 0, "disputed => was delivered");
        }
    }
}

/// @dev GLOBAL invariant, deliberately isolated: delete this contract to drop it without touching the
///      per-job invariants above. Holds for a standard token with no unsolicited transfers.
/// forge-config: default.invariant.runs = 100
/// forge-config: default.invariant.depth = 300
/// forge-config: default.invariant.fail_on_revert = false
contract FreelanceEscrowGlobalInvariantTest is EscrowInvariantSetup {
    /// USDC held == totalRemaining + totalClaimable.
    function invariant_Global_BalanceEqualsRemainingPlusClaimable() public view {
        assertEq(
            usdc.balanceOf(address(escrow)), escrow.totalRemaining() + escrow.totalClaimable(), "balance == liabilities"
        );
    }

    /// totalClaimable == Σ claimable of every actor that can be credited.
    function invariant_Global_TotalClaimableEqualsSumOfActorClaimable() public view {
        address[] memory all = handler.actors();
        uint256 sum;
        for (uint256 i; i < all.length; ++i) {
            sum += escrow.claimable(all[i]);
        }
        assertEq(escrow.totalClaimable(), sum, "totalClaimable == sum(claimable)");
    }

    /// totalRemaining == Σ remaining over all jobs.
    function invariant_Global_TotalRemainingEqualsSumOfJobRemaining() public view {
        uint256[] memory ids = handler.jobIds();
        uint256 sum;
        for (uint256 i; i < ids.length; ++i) {
            sum += escrow.getJob(ids[i]).remaining;
        }
        assertEq(escrow.totalRemaining(), sum, "totalRemaining == sum(job.remaining)");
    }
}
