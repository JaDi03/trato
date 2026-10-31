// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FreelanceEscrow} from "../FreelanceEscrow.sol";
import {FreelanceEscrowTestBase} from "./FreelanceEscrow.Base.t.sol";

/// @dev Shared fixtures for the partial-refund proposal flow. No test functions.
abstract contract FreelanceEscrowPartialBase is FreelanceEscrowTestBase {
    uint256 internal id;
    uint256 internal constant AMT = 5_000_000; // each of the 2 default milestones

    function setUp() public virtual override {
        super.setUp();
        id = _createN(TOTAL, 2); // 2 x 5_000_000, payees p1/p2 at 70/30, 1 revision, 3d review
    }

    function _propose(uint256 jobId, uint256 m, uint256 refund) internal {
        vm.prank(client);
        escrow.proposePartial(jobId, m, refund);
    }

    function _accept(uint256 jobId, uint256 m, uint256 expected) internal {
        vm.prank(freelancer);
        escrow.acceptPartial(jobId, m, expected);
    }

    function _decline(uint256 jobId, uint256 m) internal {
        vm.prank(freelancer);
        escrow.declinePartial(jobId, m);
    }

    function _cancel(uint256 jobId, uint256 m) internal {
        vm.prank(client);
        escrow.cancelPartial(jobId, m);
    }

    function _proposeRevert(bytes memory err, uint256 jobId, uint256 m, uint256 refund) internal {
        vm.prank(client);
        vm.expectRevert(err);
        escrow.proposePartial(jobId, m, refund);
    }

    function _acceptRevert(bytes memory err, uint256 jobId, uint256 m, uint256 expected) internal {
        vm.prank(freelancer);
        vm.expectRevert(err);
        escrow.acceptPartial(jobId, m, expected);
    }

    function _proposed(uint256 jobId, uint256 m) internal view returns (uint256) {
        return _ms(jobId, m).proposedRefund;
    }

    function _autoApproveBy(address who, uint256 jobId, uint256 m) internal {
        vm.prank(who);
        escrow.autoApprove(jobId, m);
    }

    /// @dev Single-milestone job paying p1/p2/p3 with the given shares.
    function _createThreePayee(uint256 total, uint16 s1, uint16 s2, uint16 s3) internal returns (uint256) {
        address[] memory a = new address[](3);
        a[0] = p1;
        a[1] = p2;
        a[2] = p3;
        uint16[] memory s = new uint16[](3);
        s[0] = s1;
        s[1] = s2;
        s[2] = s3;
        FreelanceEscrow.MilestoneInput[] memory ms = new FreelanceEscrow.MilestoneInput[](1);
        ms[0] = _inputWith(10_000, a, s, REVISIONS);
        return _create(total, ms);
    }

    function _unauthorized() internal pure returns (bytes memory) {
        return _sel(FreelanceEscrow.Unauthorized.selector);
    }

    function _noProposal() internal pure returns (bytes memory) {
        return _sel(FreelanceEscrow.NoProposal.selector);
    }
}
