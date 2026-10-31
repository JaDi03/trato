// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {FreelanceEscrow} from "../FreelanceEscrow.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

/// @dev Shared fixtures/helpers. No test functions here (every category file inherits it).
abstract contract FreelanceEscrowTestBase is Test {
    FreelanceEscrow internal escrow;
    MockUSDC internal usdc;

    address internal client = makeAddr("client");
    address internal freelancer = makeAddr("freelancer");
    address internal arbiter = makeAddr("arbiter");
    address internal p1 = makeAddr("payee1");
    address internal p2 = makeAddr("payee2");
    address internal p3 = makeAddr("payee3");
    address internal stranger = makeAddr("stranger");

    uint32 internal constant DELIVERY = 7 days;
    uint32 internal constant REVIEW = 3 days;
    uint8 internal constant REVISIONS = 1;
    uint256 internal constant T0 = 1_700_000_000;
    uint256 internal constant TOTAL = 10_000_000; // 10 USDC

    FreelanceEscrow.MilestoneState internal constant PENDING = FreelanceEscrow.MilestoneState.Pending;
    FreelanceEscrow.MilestoneState internal constant IN_PROGRESS = FreelanceEscrow.MilestoneState.InProgress;
    FreelanceEscrow.MilestoneState internal constant DELIVERED = FreelanceEscrow.MilestoneState.Delivered;
    FreelanceEscrow.MilestoneState internal constant IN_REVISION = FreelanceEscrow.MilestoneState.InRevision;
    FreelanceEscrow.MilestoneState internal constant DISPUTED = FreelanceEscrow.MilestoneState.Disputed;
    FreelanceEscrow.MilestoneState internal constant PAID = FreelanceEscrow.MilestoneState.Paid;
    FreelanceEscrow.MilestoneState internal constant REFUNDED = FreelanceEscrow.MilestoneState.Refunded;

    function setUp() public virtual {
        vm.warp(T0);
        usdc = new MockUSDC();
        escrow = new FreelanceEscrow(address(usdc));
        usdc.mint(client, 1e15);
    }

    // ------------------------------------------------------------------ builders

    function _inputWith(uint16 bps, address[] memory payees, uint16[] memory shares, uint8 revs)
        internal
        pure
        returns (FreelanceEscrow.MilestoneInput memory)
    {
        return FreelanceEscrow.MilestoneInput({
            bps: bps,
            payees: payees,
            shares: shares,
            deliveryDuration: DELIVERY,
            reviewPeriod: REVIEW,
            maxRevisions: revs
        });
    }

    /// @dev Default milestone: payees p1/p2 at 70/30, one allowed revision.
    function _input(uint16 bps) internal view returns (FreelanceEscrow.MilestoneInput memory) {
        address[] memory a = new address[](2);
        a[0] = p1;
        a[1] = p2;
        uint16[] memory s = new uint16[](2);
        s[0] = 7000;
        s[1] = 3000;
        return _inputWith(bps, a, s, REVISIONS);
    }

    function _evenInputs(uint256 n, uint8 revs) internal view returns (FreelanceEscrow.MilestoneInput[] memory ms) {
        ms = new FreelanceEscrow.MilestoneInput[](n);
        uint16 each = uint16(10_000 / n);
        uint16 acc;
        for (uint256 i; i < n; ++i) {
            ms[i] = _input(i + 1 == n ? uint16(10_000) - acc : each);
            ms[i].maxRevisions = revs;
            acc += each;
        }
    }

    function _create(uint256 total, FreelanceEscrow.MilestoneInput[] memory ms) internal returns (uint256 id) {
        vm.startPrank(client);
        usdc.approve(address(escrow), total);
        id = escrow.createJob(freelancer, arbiter, total, ms);
        vm.stopPrank();
    }

    function _createN(uint256 total, uint256 n) internal returns (uint256) {
        return _create(total, _evenInputs(n, REVISIONS));
    }

    function _createNRev(uint256 total, uint256 n, uint8 revs) internal returns (uint256) {
        return _create(total, _evenInputs(n, revs));
    }

    function _createRevert(bytes memory err, uint256 total, FreelanceEscrow.MilestoneInput[] memory ms) internal {
        vm.prank(client);
        vm.expectRevert(err);
        escrow.createJob(freelancer, arbiter, total, ms);
    }

    // ------------------------------------------------------------------ actions

    function _start(uint256 id, uint256 m) internal {
        vm.prank(freelancer);
        escrow.startMilestone(id, m);
    }

    function _deliver(uint256 id, uint256 m) internal {
        vm.prank(freelancer);
        escrow.deliver(id, m);
    }

    function _approveM(uint256 id, uint256 m) internal {
        vm.prank(client);
        escrow.approve(id, m);
    }

    function _revise(uint256 id, uint256 m) internal {
        vm.prank(client);
        escrow.requestRevision(id, m);
    }

    function _reject(uint256 id, uint256 m) internal {
        vm.prank(client);
        escrow.rejectDelivery(id, m);
    }

    function _clientDispute(uint256 id, uint256 m) internal {
        vm.prank(client);
        escrow.openDispute(id, m);
    }

    function _resolve(uint256 id, uint256 m, uint256 refund) internal {
        vm.prank(arbiter);
        escrow.resolveDispute(id, m, refund);
    }

    function _refundM(uint256 id, uint256 m) internal {
        vm.prank(client);
        escrow.refundMilestone(id, m);
    }

    function _toDelivered(uint256 id, uint256 m) internal {
        _start(id, m);
        _deliver(id, m);
    }

    /// @dev Requires REVISIONS == 1: start, deliver, revise, deliver, reject => Delivered + rejectedFinal.
    function _toRejected(uint256 id, uint256 m) internal {
        _toDelivered(id, m);
        _revise(id, m);
        _deliver(id, m);
        _reject(id, m);
    }

    function _toDisputed(uint256 id, uint256 m) internal {
        _toDelivered(id, m);
        _clientDispute(id, m);
    }

    // ------------------------------------------------------------------ views / asserts

    function _ms(uint256 id, uint256 m) internal view returns (FreelanceEscrow.Milestone memory) {
        return escrow.getMilestone(id, m);
    }

    function _assertState(uint256 id, uint256 m, FreelanceEscrow.MilestoneState s) internal view {
        assertEq(uint8(_ms(id, m).state), uint8(s), "milestone state");
    }

    function _badState(FreelanceEscrow.MilestoneState s) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(FreelanceEscrow.InvalidState.selector, s);
    }

    function _sel(bytes4 s) internal pure returns (bytes memory) {
        return abi.encodePacked(s);
    }

    function _claim(address a) internal view returns (uint256) {
        return escrow.claimable(a);
    }

    /// @dev Mirrors the contract's documented split: floor for each payee, last takes remainder.
    function _split(uint256 amount, uint16[] memory shares) internal pure returns (uint256[] memory out) {
        out = new uint256[](shares.length);
        uint256 acc;
        for (uint256 i; i < shares.length; ++i) {
            out[i] = i + 1 == shares.length ? amount - acc : (amount * shares[i]) / 10_000;
            acc += out[i];
        }
    }

    /// @dev Expect the next emitted event on the escrow with all topics + data checked.
    function _e() internal {
        vm.expectEmit(true, true, true, true, address(escrow));
    }
}
