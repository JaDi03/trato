// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FreelanceEscrow} from "../FreelanceEscrow.sol";
import {FreelanceEscrowTestBase} from "./FreelanceEscrow.Base.t.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {HookUSDC, ITokenHook} from "./mocks/TestTokens.sol";

/// @dev Payee that tries to re-enter withdraw() from the token transfer hook.
contract ReentrantPayee is ITokenHook {
    FreelanceEscrow public immutable escrow;
    bool public attempted;
    bool public succeeded;

    constructor(FreelanceEscrow e) {
        escrow = e;
    }

    function withdraw() external {
        escrow.withdraw();
    }

    function onTokenReceived() external {
        attempted = true;
        try escrow.withdraw() {
            succeeded = true;
        } catch {}
    }
}

/// @notice Pull-payment behaviour, token-blocklist isolation, reentrancy, and the "no admin" property.
contract FreelanceEscrowPullTest is FreelanceEscrowTestBase {
    uint256 internal id;

    function setUp() public override {
        super.setUp();
        id = _createN(TOTAL, 2); // 2 x 5_000_000
    }

    // ------------------------------------------------------------ withdraw

    function test_Withdraw_PaysOnlyCaller() public {
        _toDelivered(id, 0);
        _approveM(id, 0);
        uint256 escrowBal = usdc.balanceOf(address(escrow));

        vm.prank(p1);
        escrow.withdraw();

        assertEq(usdc.balanceOf(p1), 3_500_000);
        assertEq(usdc.balanceOf(p2), 0);
        assertEq(_claim(p1), 0);
        assertEq(_claim(p2), 1_500_000);
        assertEq(usdc.balanceOf(address(escrow)), escrowBal - 3_500_000);
        assertEq(escrow.totalClaimable(), 1_500_000);
        assertEq(escrow.totalRemaining(), 5_000_000);
    }

    function test_Revert_Withdraw_ZeroBalanceAndRepeat() public {
        vm.prank(stranger);
        vm.expectRevert(FreelanceEscrow.NothingToWithdraw.selector);
        escrow.withdraw();

        _toDelivered(id, 0);
        _approveM(id, 0);
        vm.prank(p2);
        escrow.withdraw();
        vm.prank(p2);
        vm.expectRevert(FreelanceEscrow.NothingToWithdraw.selector);
        escrow.withdraw();
        // roles with no credit cannot withdraw either
        vm.prank(freelancer);
        vm.expectRevert(FreelanceEscrow.NothingToWithdraw.selector);
        escrow.withdraw();
    }

    // ------------------------------------------------------------ blocklisted payee

    function test_BlockedPayee_CannotWithdraw_OthersCan() public {
        usdc.setBlocked(p1, true);
        // settlement itself is unaffected by the blocked payee
        _toDelivered(id, 0);
        _approveM(id, 0);
        assertEq(_claim(p1), 3_500_000);

        // second milestone refunded to the client
        _start(id, 1);
        vm.warp(_ms(id, 1).deadline + 1);
        _refundM(id, 1);
        assertTrue(escrow.getJob(id).completed);

        vm.prank(p1);
        vm.expectRevert(abi.encodeWithSelector(MockUSDC.Blocked.selector, p1));
        escrow.withdraw();
        assertEq(_claim(p1), 3_500_000, "blocked payee credit preserved");

        vm.prank(p2);
        escrow.withdraw();
        assertEq(usdc.balanceOf(p2), 1_500_000);
        vm.prank(client);
        escrow.withdraw();
        assertEq(usdc.balanceOf(client), 1e15 - TOTAL + 5_000_000);

        // funds of the blocked payee stay reserved; unblocking lets them out
        assertEq(usdc.balanceOf(address(escrow)), 3_500_000);
        usdc.setBlocked(p1, false);
        vm.prank(p1);
        escrow.withdraw();
        assertEq(usdc.balanceOf(p1), 3_500_000);
        assertEq(usdc.balanceOf(address(escrow)), 0);
    }

    function test_BlockedClient_CannotFundNewJob() public {
        usdc.setBlocked(client, true);
        FreelanceEscrow.MilestoneInput[] memory ms = _evenInputs(1, 0);
        vm.startPrank(client);
        // approve is not a transfer, so it goes through; transferFrom reverts
        usdc.approve(address(escrow), TOTAL);
        vm.expectRevert(abi.encodeWithSelector(MockUSDC.Blocked.selector, client));
        escrow.createJob(freelancer, arbiter, TOTAL, ms);
        vm.stopPrank();
        assertEq(escrow.jobCount(), 1);
    }

    // ------------------------------------------------------------ reentrancy

    function test_Withdraw_ReentrancyIsBlocked() public {
        HookUSDC hook = new HookUSDC();
        escrow = new FreelanceEscrow(address(hook));
        usdc = hook;
        usdc.mint(client, 1e15);
        ReentrantPayee atk = new ReentrantPayee(escrow);

        address[] memory ps = new address[](1);
        ps[0] = address(atk);
        uint16[] memory sh = new uint16[](1);
        sh[0] = 10_000;
        FreelanceEscrow.MilestoneInput[] memory ms = new FreelanceEscrow.MilestoneInput[](1);
        ms[0] = _inputWith(10_000, ps, sh, 0);
        uint256 jobA = _create(TOTAL, ms); // attacker is the payee
        uint256 jobB = _create(TOTAL, _evenInputs(1, 0)); // innocent job holding extra funds
        assertEq(jobB, 2);

        _toDelivered(jobA, 0);
        _approveM(jobA, 0);
        hook.setHookTarget(address(atk));

        atk.withdraw();

        assertTrue(atk.attempted(), "hook ran");
        assertFalse(atk.succeeded(), "re-entry must fail");
        assertEq(usdc.balanceOf(address(atk)), TOTAL);
        assertEq(usdc.balanceOf(address(escrow)), TOTAL, "other job funds untouched");
        assertEq(escrow.totalRemaining(), TOTAL);
        assertEq(escrow.totalClaimable(), 0);
        assertEq(_claim(address(atk)), 0);
    }

    // ------------------------------------------------------------ no admin / no backdoor

    function test_NoAdminFunctions_ExistInAbi() public {
        string[12] memory sigs = [
            "owner()",
            "pause()",
            "unpause()",
            "paused()",
            "rescue(address,uint256)",
            "rescueTokens(address,uint256)",
            "sweep(address)",
            "sweep(address,uint256)",
            "emergencyWithdraw()",
            "transferOwnership(address)",
            "renounceOwnership()",
            "setArbiter(uint256,address)"
        ];
        for (uint256 i; i < sigs.length; ++i) {
            (bool ok,) = address(escrow).call(abi.encodeWithSignature(sigs[i], address(this), uint256(1)));
            assertFalse(ok, sigs[i]);
            vm.prank(client);
            (ok,) = address(escrow).call(abi.encodeWithSignature(sigs[i], address(this), uint256(1)));
            assertFalse(ok, sigs[i]);
        }
    }

    function test_NoFallbackOrReceive_EthRejected() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(escrow).call{value: 1 wei}("");
        assertFalse(ok);
        (ok,) = address(escrow).call{value: 1 wei}(hex"deadbeef");
        assertFalse(ok);
    }

    function test_NoOneCanPullFunds_ExceptThroughWithdraw() public {
        // 10 USDC locked in the job + 100 unsolicited USDC donated directly
        usdc.mint(address(escrow), 100e6);
        uint256 locked = usdc.balanceOf(address(escrow));
        assertEq(locked, TOTAL + 100e6);

        address[6] memory actors = [client, freelancer, arbiter, stranger, p1, p2];
        for (uint256 i; i < actors.length; ++i) {
            vm.prank(actors[i]);
            vm.expectRevert(FreelanceEscrow.NothingToWithdraw.selector);
            escrow.withdraw();
        }
        // every privileged-looking action by a non-authorised party leaves the balance untouched
        vm.startPrank(stranger);
        vm.expectRevert(FreelanceEscrow.Unauthorized.selector);
        escrow.declineJob(id);
        vm.expectRevert(FreelanceEscrow.Unauthorized.selector);
        escrow.refundMilestone(id, 0);
        vm.expectRevert(FreelanceEscrow.Unauthorized.selector);
        escrow.resolveDispute(id, 0, 0);
        vm.stopPrank();
        assertEq(usdc.balanceOf(address(escrow)), locked);
        assertEq(usdc.balanceOf(stranger), 0);
    }

    function test_UnsolicitedDonation_IsNotWithdrawable() public {
        usdc.mint(address(escrow), 777);
        vm.prank(freelancer);
        escrow.declineJob(id);
        vm.prank(client);
        escrow.withdraw();
        // only the 10 USDC deposit left; the donation is stranded, not claimable by anyone
        assertEq(usdc.balanceOf(address(escrow)), 777);
        assertEq(escrow.totalClaimable(), 0);
        assertEq(escrow.totalRemaining(), 0);
    }
}
