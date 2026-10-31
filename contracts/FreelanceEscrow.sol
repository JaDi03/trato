// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title FreelanceEscrow
/// @notice Multi-job USDC escrow with sequential milestones and isolated pull payments.
/// @dev Amounts are raw USDC units (6 decimals). There is no administrator or recovery path.
///      For a standard, non-rebasing USDC token, balance equals totalRemaining + totalClaimable
///      absent unsolicited token transfers. Unsolicited surplus cannot be withdrawn or assigned.
contract FreelanceEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant DISPUTE_TIMEOUT = 30 days;
    uint256 public constant REJECTION_REFUND_DELAY = 7 days;
    uint256 public constant START_WINDOW = 14 days;
    uint256 private constant BPS = 10_000;

    IERC20 public immutable usdc;
    uint256 public jobCount;
    mapping(address => uint256) public claimable;
    uint256 public totalClaimable;
    uint256 public totalRemaining;

    enum MilestoneState {
        Pending,
        InProgress,
        Delivered,
        Approved,
        InRevision,
        Disputed,
        Paid,
        Refunded
    }

    struct MilestoneInput {
        uint16 bps;
        address[] payees;
        uint16[] shares;
        uint32 deliveryDuration;
        uint32 reviewPeriod;
        uint8 maxRevisions;
    }

    struct Milestone {
        uint256 amount;
        uint16 bps;
        uint32 deliveryDuration;
        uint32 reviewPeriod;
        uint8 maxRevisions;
        uint8 revisionsUsed;
        MilestoneState state;
        uint256 unlockedAt;
        uint256 startedAt;
        uint256 deadline;
        uint256 deliveredAt;
        bool rejectedFinal;
        uint256 rejectedAt;
        uint256 disputedAt;
        address[] payees;
        uint16[] shares;
        uint256 proposedRefund;
    }

    struct Job {
        uint256 id;
        address client;
        address freelancer;
        address arbiter;
        uint256 deposited;
        uint256 paid;
        uint256 refunded;
        uint256 remaining;
        bool completed;
        uint256 createdAt;
        Milestone[] milestones;
    }

    /// @notice Named job summary; total is the original deposit, in raw USDC units.
    struct JobView {
        address client;
        address freelancer;
        address arbiter;
        uint256 total;
        uint256 paid;
        uint256 refunded;
        uint256 remaining;
        uint256 milestoneCount;
        bool completed;
        uint256 createdAt;
    }

    mapping(uint256 => Job) private _jobs;
    mapping(address => uint256[]) private _addressJobs;
    mapping(address => uint256) private _lastIndexedJob;

    error ZeroAddress();
    error InvalidToken();
    error InvalidRoles();
    error InvalidTotal();
    error InvalidMilestoneCount();
    error InvalidPayeeCount();
    error InvalidBasisPoints();
    error InvalidShares();
    error DuplicatePayee(address payee);
    error InvalidDuration();
    error FundingMismatch(uint256 expected, uint256 received);
    error JobNotFound(uint256 jobId);
    error MilestoneNotFound(uint256 milestone);
    error Unauthorized();
    error InvalidState(MilestoneState actual);
    error MilestoneLocked();
    error TooEarly();
    error ReviewPeriodExpired();
    error RevisionsExhausted();
    error RevisionsAvailable();
    error AlreadyRejected();
    error NotRejected();
    error InvalidRefund();
    error NoProposal();
    error ProposalMismatch(uint256 proposed, uint256 expected);
    error JobAlreadyCompleted();
    error NothingToWithdraw();

    event JobCreated(
        uint256 indexed jobId,
        address indexed client,
        address indexed freelancer,
        address arbiter,
        uint256 total,
        uint256 milestoneCount,
        uint256 createdAt
    );
    event MilestoneUnlocked(uint256 indexed jobId, uint256 indexed milestone, uint256 unlockedAt);
    event MilestoneStarted(uint256 indexed jobId, uint256 indexed milestone, uint256 startedAt, uint256 deadline);
    event MilestoneDelivered(uint256 indexed jobId, uint256 indexed milestone, uint256 deliveredAt);
    event MilestoneApproved(uint256 indexed jobId, uint256 indexed milestone, bool automatic);
    event RevisionRequested(uint256 indexed jobId, uint256 indexed milestone, uint8 revisionsUsed, uint256 deadline);
    event DeliveryRejected(uint256 indexed jobId, uint256 indexed milestone, uint256 rejectedAt);
    event DisputeOpened(uint256 indexed jobId, uint256 indexed milestone, address indexed by);
    event DisputeResolved(uint256 indexed jobId, uint256 indexed milestone, uint256 clientRefund, uint256 payeeAmount);
    event DisputeTimedOut(uint256 indexed jobId, uint256 indexed milestone);
    event MilestonePaid(uint256 indexed jobId, uint256 indexed milestone, uint256 payeeAmount, uint256 clientRefund);
    event MilestoneRefunded(uint256 indexed jobId, uint256 indexed milestone, uint256 amount);
    event JobDeclined(uint256 indexed jobId);
    event JobCompleted(uint256 indexed jobId);
    event Credited(address indexed to, uint256 amount, uint256 indexed jobId);
    event Withdrawn(address indexed to, uint256 amount);
    event PartialProposed(uint256 indexed jobId, uint256 indexed m, uint256 clientRefund);
    event PartialAccepted(uint256 indexed jobId, uint256 indexed m, uint256 clientRefund);
    event PartialDeclined(uint256 indexed jobId, uint256 indexed m);
    event PartialCancelled(uint256 indexed jobId, uint256 indexed m);

    /// @param token The USDC ERC-20 contract on the deployment network; cannot be replaced.
    constructor(address token) {
        if (token == address(0)) revert ZeroAddress();
        if (token.code.length == 0) revert InvalidToken();
        usdc = IERC20(token);
    }

    /// @notice Create and fully fund a job; caller must first approve this contract for total.
    /// @dev Every basis-point allocation floors except the last entry, which receives the remainder.
    function createJob(
        address freelancer,
        address arbiter,
        uint256 total,
        MilestoneInput[] calldata ms
    ) external nonReentrant returns (uint256 jobId) {
        if (freelancer == address(0) || arbiter == address(0)) revert ZeroAddress();
        if (freelancer == msg.sender || arbiter == msg.sender || arbiter == freelancer) revert InvalidRoles();
        if (total == 0) revert InvalidTotal();
        if (ms.length == 0 || ms.length > 20) revert InvalidMilestoneCount();

        jobId = ++jobCount;
        Job storage job = _jobs[jobId];
        job.id = jobId;
        job.client = msg.sender;
        job.freelancer = freelancer;
        job.arbiter = arbiter;
        job.deposited = total;
        job.remaining = total;
        job.createdAt = block.timestamp;
        _index(msg.sender, jobId);
        _index(freelancer, jobId);
        _index(arbiter, jobId);

        uint256 sumBps;
        uint256 allocated;
        for (uint256 i; i < ms.length; ++i) {
            MilestoneInput calldata input = ms[i];
            _validateMilestone(input, arbiter);
            sumBps += input.bps;
            // Bound the running sum before calculating the remainder (including for the last entry).
            if (sumBps > BPS) revert InvalidBasisPoints();
            uint256 amount = i + 1 == ms.length ? total - allocated : Math.mulDiv(total, input.bps, BPS);
            allocated += amount;
            Milestone storage milestone = job.milestones.push();
            milestone.amount = amount;
            milestone.bps = input.bps;
            milestone.deliveryDuration = input.deliveryDuration;
            milestone.reviewPeriod = input.reviewPeriod;
            milestone.maxRevisions = input.maxRevisions;
            if (i == 0) milestone.unlockedAt = block.timestamp;
            for (uint256 p; p < input.payees.length; ++p) {
                milestone.payees.push(input.payees[p]);
                milestone.shares.push(input.shares[p]);
                _index(input.payees[p], jobId);
            }
        }
        if (sumBps != BPS) revert InvalidBasisPoints();
        totalRemaining += total;

        uint256 beforeBalance = usdc.balanceOf(address(this));
        usdc.safeTransferFrom(msg.sender, address(this), total);
        uint256 afterBalance = usdc.balanceOf(address(this));
        uint256 received = afterBalance >= beforeBalance ? afterBalance - beforeBalance : 0;
        if (afterBalance < beforeBalance || received != total) revert FundingMismatch(total, received);
        emit JobCreated(jobId, msg.sender, freelancer, arbiter, total, ms.length, block.timestamp);
        emit MilestoneUnlocked(jobId, 0, block.timestamp);
    }

    /// @notice Begin an unlocked milestone and establish its delivery deadline.
    /// @dev Deadlines are soft: refund rights are options the client must exercise before the freelancer acts.
    function startMilestone(uint256 jobId, uint256 m) external nonReentrant {
        Job storage job = _job(jobId);
        _onlyFreelancer(job);
        Milestone storage milestone = _milestone(job, m);
        _requireState(milestone, MilestoneState.Pending);
        _requireUnlocked(job, m);
        milestone.state = MilestoneState.InProgress;
        milestone.startedAt = block.timestamp;
        milestone.deadline = block.timestamp + milestone.deliveryDuration;
        emit MilestoneStarted(jobId, m, milestone.startedAt, milestone.deadline);
    }

    /// @notice Deliver work, even after its deadline if the client has not already refunded it.
    /// @dev Deadlines are soft: refund rights are options the client must exercise before the freelancer acts.
    function deliver(uint256 jobId, uint256 m) external nonReentrant {
        Job storage job = _job(jobId);
        _onlyFreelancer(job);
        Milestone storage milestone = _milestone(job, m);
        if (milestone.state != MilestoneState.InProgress && milestone.state != MilestoneState.InRevision) {
            revert InvalidState(milestone.state);
        }
        milestone.proposedRefund = 0;
        milestone.state = MilestoneState.Delivered;
        milestone.deliveredAt = block.timestamp;
        emit MilestoneDelivered(jobId, m, milestone.deliveredAt);
    }

    /// @notice Accept a delivery and immediately credit its payees, including after final rejection.
    function approve(uint256 jobId, uint256 m) external nonReentrant {
        Job storage job = _job(jobId);
        _onlyClient(job);
        Milestone storage milestone = _milestone(job, m);
        _requireState(milestone, MilestoneState.Delivered);
        _approve(job, milestone, m, false);
    }

    /// @notice Propose or replace a partial refund requiring freelancer acceptance.
    /// @dev No review-window limit; proposals move no funds and do not restrict other milestone actions.
    function proposePartial(uint256 jobId, uint256 m, uint256 clientRefund) external nonReentrant {
        Job storage job = _job(jobId);
        _onlyClient(job);
        Milestone storage milestone = _milestone(job, m);
        _requireState(milestone, MilestoneState.Delivered);
        if (clientRefund == 0 || clientRefund >= milestone.amount) revert InvalidRefund();
        milestone.proposedRefund = clientRefund;
        emit PartialProposed(jobId, m, clientRefund);
    }

    /// @notice Accept the proposed client refund and credit the remaining amount to payees.
    /// @param expectedClientRefund The exact refund agreed to, protecting against changed proposal terms.
    function acceptPartial(uint256 jobId, uint256 m, uint256 expectedClientRefund) external nonReentrant {
        Job storage job = _job(jobId);
        _onlyFreelancer(job);
        Milestone storage milestone = _milestone(job, m);
        _requireState(milestone, MilestoneState.Delivered);
        uint256 clientRefund = milestone.proposedRefund;
        if (clientRefund == 0) revert NoProposal();
        if (clientRefund != expectedClientRefund) revert ProposalMismatch(clientRefund, expectedClientRefund);
        if (clientRefund == 0 || clientRefund >= milestone.amount) revert InvalidRefund();
        uint256 payeeAmount = milestone.amount - clientRefund;
        milestone.proposedRefund = 0;
        emit PartialAccepted(jobId, m, clientRefund);
        milestone.state = MilestoneState.Approved;
        emit MilestoneApproved(jobId, m, false);
        _settleClient(job, milestone, clientRefund);
        _settlePayees(job, milestone, payeeAmount);
        milestone.state = MilestoneState.Paid;
        emit MilestonePaid(jobId, m, payeeAmount, clientRefund);
        _afterSettlement(job, m);
    }

    /// @notice Decline a partial refund proposal without changing any other milestone rights.
    function declinePartial(uint256 jobId, uint256 m) external nonReentrant {
        Job storage job = _job(jobId);
        _onlyFreelancer(job);
        Milestone storage milestone = _milestone(job, m);
        _requireState(milestone, MilestoneState.Delivered);
        if (milestone.proposedRefund == 0) revert NoProposal();
        milestone.proposedRefund = 0;
        emit PartialDeclined(jobId, m);
    }

    /// @notice Cancel a partial refund proposal without changing any other milestone rights.
    function cancelPartial(uint256 jobId, uint256 m) external nonReentrant {
        Job storage job = _job(jobId);
        _onlyClient(job);
        Milestone storage milestone = _milestone(job, m);
        _requireState(milestone, MilestoneState.Delivered);
        if (milestone.proposedRefund == 0) revert NoProposal();
        milestone.proposedRefund = 0;
        emit PartialCancelled(jobId, m);
    }

    /// @notice Credit payees after the review window unless the delivery was finally rejected.
    function autoApprove(uint256 jobId, uint256 m) external nonReentrant {
        Job storage job = _job(jobId);
        Milestone storage milestone = _milestone(job, m);
        _requireState(milestone, MilestoneState.Delivered);
        if (milestone.rejectedFinal) revert AlreadyRejected();
        if (block.timestamp < milestone.deliveredAt + milestone.reviewPeriod) revert TooEarly();
        _approve(job, milestone, m, true);
    }

    /// @notice Request a permitted revision with a fresh delivery deadline.
    function requestRevision(uint256 jobId, uint256 m) external nonReentrant {
        Job storage job = _job(jobId);
        _onlyClient(job);
        Milestone storage milestone = _milestone(job, m);
        _requireState(milestone, MilestoneState.Delivered);
        if (block.timestamp >= milestone.deliveredAt + milestone.reviewPeriod) revert ReviewPeriodExpired();
        if (milestone.revisionsUsed >= milestone.maxRevisions) revert RevisionsExhausted();
        ++milestone.revisionsUsed;
        milestone.state = MilestoneState.InRevision;
        milestone.deadline = block.timestamp + milestone.deliveryDuration;
        emit RevisionRequested(jobId, m, milestone.revisionsUsed, milestone.deadline);
    }

    /// @notice Finally reject a delivery only after all permitted revisions have been used.
    function rejectDelivery(uint256 jobId, uint256 m) external nonReentrant {
        Job storage job = _job(jobId);
        _onlyClient(job);
        Milestone storage milestone = _milestone(job, m);
        _requireState(milestone, MilestoneState.Delivered);
        if (block.timestamp >= milestone.deliveredAt + milestone.reviewPeriod) revert ReviewPeriodExpired();
        if (milestone.revisionsUsed != milestone.maxRevisions) revert RevisionsAvailable();
        if (milestone.rejectedFinal) revert AlreadyRejected();
        milestone.rejectedFinal = true;
        milestone.rejectedAt = block.timestamp;
        emit DeliveryRejected(jobId, m, milestone.rejectedAt);
    }

    /// @notice Client may dispute any delivered work; freelancer may dispute a final rejection.
    /// @dev For freelancer disputes, deadlines are soft: refund rights are options the client must exercise
    ///      before the freelancer acts.
    function openDispute(uint256 jobId, uint256 m) external nonReentrant {
        Job storage job = _job(jobId);
        Milestone storage milestone = _milestone(job, m);
        _requireState(milestone, MilestoneState.Delivered);
        if (msg.sender != job.client && !(msg.sender == job.freelancer && milestone.rejectedFinal)) {
            revert Unauthorized();
        }
        if (
            msg.sender == job.client && !milestone.rejectedFinal
                && block.timestamp >= milestone.deliveredAt + milestone.reviewPeriod
        ) revert ReviewPeriodExpired();
        milestone.state = MilestoneState.Disputed;
        milestone.disputedAt = block.timestamp;
        emit DisputeOpened(jobId, m, msg.sender);
        if (m + 1 < job.milestones.length && job.milestones[m + 1].unlockedAt == 0) {
            job.milestones[m + 1].unlockedAt = block.timestamp;
            emit MilestoneUnlocked(job.id, m + 1, block.timestamp);
        }
    }

    /// @notice Arbiter credits a chosen client refund and allocates the rest to payees.
    function resolveDispute(uint256 jobId, uint256 m, uint256 clientRefund) external nonReentrant {
        Job storage job = _job(jobId);
        if (msg.sender != job.arbiter) revert Unauthorized();
        Milestone storage milestone = _milestone(job, m);
        _requireState(milestone, MilestoneState.Disputed);
        if (clientRefund > milestone.amount) revert InvalidRefund();
        _resolve(job, milestone, m, clientRefund);
    }

    /// @notice After thirty days anyone can split a dispute; an odd raw unit goes to payees.
    function resolveDisputeByTimeout(uint256 jobId, uint256 m) external nonReentrant {
        Job storage job = _job(jobId);
        Milestone storage milestone = _milestone(job, m);
        _requireState(milestone, MilestoneState.Disputed);
        if (block.timestamp < milestone.disputedAt + DISPUTE_TIMEOUT) revert TooEarly();
        emit DisputeTimedOut(jobId, m);
        _resolve(job, milestone, m, milestone.amount / 2);
    }

    /// @notice Refund late undelivered work, or unlocked work not started within fourteen days.
    function refundMilestone(uint256 jobId, uint256 m) external nonReentrant {
        Job storage job = _job(jobId);
        _onlyClient(job);
        Milestone storage milestone = _milestone(job, m);
        if (milestone.state == MilestoneState.Pending) {
            _requireUnlocked(job, m);
            if (block.timestamp <= milestone.unlockedAt + START_WINDOW) revert TooEarly();
        } else if (milestone.state == MilestoneState.InProgress || milestone.state == MilestoneState.InRevision) {
            if (block.timestamp <= milestone.deadline) revert TooEarly();
        } else {
            revert InvalidState(milestone.state);
        }
        _refund(job, milestone, m);
    }

    /// @notice Refund a final rejection after seven days if no dispute or settlement intervened.
    function refundAfterRejection(uint256 jobId, uint256 m) external nonReentrant {
        Job storage job = _job(jobId);
        _onlyClient(job);
        Milestone storage milestone = _milestone(job, m);
        _requireState(milestone, MilestoneState.Delivered);
        if (!milestone.rejectedFinal) revert NotRejected();
        if (block.timestamp < milestone.rejectedAt + REJECTION_REFUND_DELAY) revert TooEarly();
        _refund(job, milestone, m);
    }

    /// @notice Decline an unstarted job and credit every milestone back to its client.
    function declineJob(uint256 jobId) external nonReentrant {
        Job storage job = _job(jobId);
        _onlyFreelancer(job);
        if (job.completed) revert JobAlreadyCompleted();
        _requireState(job.milestones[0], MilestoneState.Pending);
        emit JobDeclined(jobId);
        for (uint256 m; m < job.milestones.length; ++m) {
            _refund(job, job.milestones[m], m);
        }
    }

    /// @notice Withdraw the caller's entire credit. A token-blocked recipient affects only itself.
    function withdraw() external nonReentrant {
        uint256 amount = claimable[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        claimable[msg.sender] = 0;
        totalClaimable -= amount;
        emit Withdrawn(msg.sender, amount);
        usdc.safeTransfer(msg.sender, amount);
    }

    /// @notice Return the job's roles, accounting, and lifecycle summary.
    function getJob(uint256 jobId) external view returns (JobView memory result) {
        Job storage job = _job(jobId);
        result = JobView({
            client: job.client,
            freelancer: job.freelancer,
            arbiter: job.arbiter,
            total: job.deposited,
            paid: job.paid,
            refunded: job.refunded,
            remaining: job.remaining,
            milestoneCount: job.milestones.length,
            completed: job.completed,
            createdAt: job.createdAt
        });
    }

    /// @notice Return all milestone fields, including payees and their shares.
    /// @dev The proposed refund is exposed only while the milestone is Delivered; otherwise it is zero.
    function getMilestone(uint256 jobId, uint256 m) external view returns (Milestone memory milestone) {
        milestone = _milestone(_job(jobId), m);
        if (milestone.state != MilestoneState.Delivered) milestone.proposedRefund = 0;
    }

    /// @notice Return ordered payees and corresponding basis-point shares.
    function getPayees(uint256 jobId, uint256 m) external view returns (address[] memory payees, uint16[] memory shares) {
        Milestone storage milestone = _milestone(_job(jobId), m);
        return (milestone.payees, milestone.shares);
    }

    /// @notice Return every job involving an address, once per job and in creation order.
    function jobsOf(address participant) external view returns (uint256[] memory jobIds) {
        return _addressJobs[participant];
    }

    function _validateMilestone(MilestoneInput calldata input, address arbiter) private pure {
        if (input.bps == 0) revert InvalidBasisPoints();
        if (input.deliveryDuration == 0 || input.reviewPeriod == 0) revert InvalidDuration();
        uint256 length = input.payees.length;
        if (length == 0 || length > 10) revert InvalidPayeeCount();
        if (length != input.shares.length) revert InvalidShares();
        uint256 sum;
        for (uint256 p; p < length; ++p) {
            address payee = input.payees[p];
            if (payee == address(0)) revert ZeroAddress();
            if (payee == arbiter) revert InvalidRoles();
            if (input.shares[p] == 0) revert InvalidShares();
            sum += input.shares[p];
            for (uint256 q; q < p; ++q) {
                if (input.payees[q] == payee) revert DuplicatePayee(payee);
            }
        }
        if (sum != BPS) revert InvalidShares();
    }

    function _index(address participant, uint256 jobId) private {
        if (_lastIndexedJob[participant] != jobId) {
            _lastIndexedJob[participant] = jobId;
            _addressJobs[participant].push(jobId);
        }
    }

    function _job(uint256 jobId) private view returns (Job storage job) {
        job = _jobs[jobId];
        if (job.client == address(0)) revert JobNotFound(jobId);
    }

    function _milestone(Job storage job, uint256 m) private view returns (Milestone storage milestone) {
        if (m >= job.milestones.length) revert MilestoneNotFound(m);
        milestone = job.milestones[m];
    }

    function _onlyClient(Job storage job) private view {
        if (msg.sender != job.client) revert Unauthorized();
    }

    function _onlyFreelancer(Job storage job) private view {
        if (msg.sender != job.freelancer) revert Unauthorized();
    }

    function _requireState(Milestone storage milestone, MilestoneState expected) private view {
        if (milestone.state != expected) revert InvalidState(milestone.state);
    }

    function _requireUnlocked(Job storage job, uint256 m) private view {
        if (
            m != 0 && !_terminal(job.milestones[m - 1].state)
                && job.milestones[m - 1].state != MilestoneState.Disputed
        ) revert MilestoneLocked();
    }

    function _terminal(MilestoneState state) private pure returns (bool) {
        return state == MilestoneState.Paid || state == MilestoneState.Refunded;
    }

    function _approve(Job storage job, Milestone storage milestone, uint256 m, bool automatic) private {
        milestone.proposedRefund = 0;
        milestone.state = MilestoneState.Approved;
        emit MilestoneApproved(job.id, m, automatic);
        _settlePayees(job, milestone, milestone.amount);
        milestone.state = MilestoneState.Paid;
        emit MilestonePaid(job.id, m, milestone.amount, 0);
        _afterSettlement(job, m);
    }

    function _resolve(Job storage job, Milestone storage milestone, uint256 m, uint256 clientRefund) private {
        milestone.proposedRefund = 0;
        uint256 payeeAmount = milestone.amount - clientRefund;
        emit DisputeResolved(job.id, m, clientRefund, payeeAmount);
        _settleClient(job, milestone, clientRefund);
        _settlePayees(job, milestone, payeeAmount);
        milestone.state = MilestoneState.Paid;
        emit MilestonePaid(job.id, m, payeeAmount, clientRefund);
        _afterSettlement(job, m);
    }

    function _refund(Job storage job, Milestone storage milestone, uint256 m) private {
        milestone.proposedRefund = 0;
        _settleClient(job, milestone, milestone.amount);
        milestone.state = MilestoneState.Refunded;
        emit MilestoneRefunded(job.id, m, milestone.amount);
        _afterSettlement(job, m);
    }

    /// @dev All payee accounting flows through here. Zero amounts remain valid for rounded milestones.
    function _settlePayees(Job storage job, Milestone storage milestone, uint256 payeeAmount) private {
        job.paid += payeeAmount;
        job.remaining -= payeeAmount;
        totalRemaining -= payeeAmount;
        totalClaimable += payeeAmount;
        uint256 allocated;
        uint256 length = milestone.payees.length;
        for (uint256 p; p < length; ++p) {
            uint256 amount = p + 1 == length
                ? payeeAmount - allocated
                : Math.mulDiv(payeeAmount, milestone.shares[p], BPS);
            allocated += amount;
            _credit(job.id, milestone.payees[p], amount);
        }
    }

    /// @dev All client refund accounting flows through here, including dispute splits and declines.
    function _settleClient(Job storage job, Milestone storage, uint256 clientAmount) private {
        job.refunded += clientAmount;
        job.remaining -= clientAmount;
        totalRemaining -= clientAmount;
        totalClaimable += clientAmount;
        _credit(job.id, job.client, clientAmount);
    }

    function _credit(uint256 jobId, address to, uint256 amount) private {
        claimable[to] += amount;
        emit Credited(to, amount, jobId);
    }

    /// @dev Completion uses terminal states, not remaining == 0: rounding can create zero-value milestones.
    function _afterSettlement(Job storage job, uint256 m) private {
        if (m + 1 < job.milestones.length && job.milestones[m + 1].unlockedAt == 0) {
            job.milestones[m + 1].unlockedAt = block.timestamp;
            emit MilestoneUnlocked(job.id, m + 1, block.timestamp);
        }
        for (uint256 i; i < job.milestones.length; ++i) {
            if (!_terminal(job.milestones[i].state)) return;
        }
        job.completed = true;
        emit JobCompleted(job.id);
    }
}
