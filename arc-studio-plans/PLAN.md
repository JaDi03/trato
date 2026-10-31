## Implementation Plan: Freelance Escrow

### Summary
A job-based escrow on Arc Testnet. A client funds a whole job in USDC upfront. The money is released milestone by milestone, and a freelancer, payees and an arbiter each get their own actions. The UI talks in dollars and plain words ("payment held in escrow"), with no wallet or gas jargon.

### Architecture
- **Blockchain:** Arc Testnet (chain 5042002). USDC is the payment token (ERC-20 view, 6 decimals, address from `@/onchain-facts`). Network fees are paid in USDC too, so there is no second token to explain.
- **Contract:** one `FreelanceEscrow` contract that holds many jobs.
  - **Admin:** no owner, no admin and no upgrade hooks, so nobody can move funds outside the rules.
  - **Safety:** USDC is handled with SafeERC20 and a reentrancy guard. Deposits are checked by balance change.
  - **Roles per job:** `client`, one lead `freelancer`, one `arbiter`. The arbiter cannot be the client, the freelancer or any payee.
  - **Create and fund:** `createJob(freelancer, arbiter, totalAmount, MilestoneInput[])` creates and funds the job in one transaction. A job can never exist unfunded. The UI shows this as "Step 1: allow payment, Step 2: fund job".
  - **Milestone inputs:** `bps`, `payees[]`, `shares[]` (sum 10000), `deliveryDuration`, `reviewPeriod` and `maxRevisions`.
  - **Validation:** milestone bps must sum to 10000 and each milestone's shares must sum to 10000, otherwise it reverts. Other limits are no zero values, no duplicate payees, at most 20 milestones and at most 10 payees per milestone.
  - **Amounts:** milestone amount = `total * bps / 10000`. The last milestone takes the rounding remainder. Within a milestone, the last payee takes the remainder, so no dust is left behind.
  - **States:** `Pending, InProgress, Delivered, Approved, InRevision, Disputed, Paid, Refunded`. `Refunded` is added because a missed-deadline refund needs its own end state.
  - **Sequence:** milestone N+1 can only start once milestone N is `Paid` or `Refunded`.
  - **Freelancer actions:**
    - `startMilestone`: Pending to InProgress. The delivery duration starts counting here, so a late milestone never expires early.
    - `deliver`: InProgress or InRevision to Delivered. This starts the review timer.
  - **Client actions** (only while Delivered):
    - `approve`: moves the state to Approved and then Paid in the same transaction, and credits each payee's share. Approved is brief but still emitted.
    - `requestRevision`: moves to InRevision and gives a fresh delivery window. It reverts once `maxRevisions` is used up.
    - `rejectDelivery`: only allowed once revisions are used up. It records the final rejection and blocks auto-approve.
    - `openDispute`: moves to Disputed.
  - **Auto-approve:** `autoApprove` can be called by anyone once `deliveredAt + reviewPeriod` has passed. It is blocked if the client already gave a final rejection.
  - **Disputes:**
    - The client can open a dispute on a Delivered milestone.
    - The freelancer can open one only after the client has used all revisions and issued a final rejection.
    - A dispute freezes only that milestone.
    - `resolveDispute(jobId, m, clientRefund)` is arbiter-only. It refunds `clientRefund` (0 up to the milestone amount) to the client and splits the rest among payees by share.
    - Timeout (added): if the arbiter does nothing for 30 days, anyone can call a timeout settlement that splits 50/50. Funds can't stay locked, and no admin is needed. Can be removed if not wanted.
  - **Missed deadlines and stuck milestones (all end in `Refunded`, credited to the client's balance):**
    - `refundMilestone`: the client can refund an InProgress or InRevision milestone after its deadline.
    - Unstarted milestones: the client can also refund an unstarted milestone 14 days after it unlocked, so a freelancer who never starts can't lock the money.
    - Final rejection (lock fix): `rejectDelivery` stores `rejectedAt`. If the freelancer has not opened a dispute within 7 days, the client can call `refundAfterRejection` and get the whole milestone back. Until that refund happens, the freelancer can still open a dispute. Once the refund is done the milestone is closed.
  - **Declining a job (optional):** `declineJob(jobId)` is freelancer-only and only works while milestone 1 is still Pending. It refunds the full deposit to the client's balance, marks every milestone Refunded and ends the job (`JobDeclined`, then `JobCompleted`). Once the freelancer starts milestone 1, they have accepted the job and its arbiter, so declining is no longer possible.
  - **Pull payments:** settlements only credit internal balances, for payees and for client refunds. `withdraw()` pays out the caller's own balance. A blocked address can only block itself.
  - **Views:** `getJob`, `getMilestone`, `getPayees`, `jobsOf(address)` (so the app needs no indexer) and `balanceOf(address)`.
  - **Events** for every state change: `JobCreated`, `MilestoneStarted`, `MilestoneDelivered`, `RevisionRequested`, `DeliveryRejected`, `MilestoneApproved` (with an auto flag), `DisputeOpened`, `DisputeResolved`, `MilestoneRefunded`, `MilestonePaid`, `Credited`, `Withdrawn`, `JobDeclined` and `JobCompleted`. The final-rejection event records `rejectedAt`.
  - **Accounting invariant, per job:** `deposited = paid + refunded + remaining`.
  - **Accounting invariant, global:** the contract's USDC balance equals unsettled milestone amounts plus unwithdrawn balances.
- **Frontend:** React, Tailwind, wagmi and viem, with ConnectKit for the wallet.
  - **Language:** dollar amounts only. Status words like "Waiting for work", "Ready for your review", "In revision", "Paid", "Refunded" and "In dispute".
  - **Durations:** shown in days.
  - **Roles:** the app shows each person only the actions that apply to them on each job.
  - **Fees:** network fees are not shown.
  - **Transactions:** each one shows plain progress ("Confirming...").
  - **Chain:** the app switches to the configured chain automatically.
  - **Arbiter visibility:** the job screen shows the arbiter's address in a plain "Disputes are decided by..." card. The freelancer's Start button says that starting work means accepting this arbiter. The freelancer also sees a "Decline job" button until they start the first milestone.
- **Configuration (env-driven):** `VITE_CHAIN_ID`, `VITE_RPC_URL`, `VITE_USDC_ADDRESS` and `VITE_ESCROW_ADDRESS`. Nothing in `src/` hardcodes a chain or token. The chain object, explorer links and USDC decimals come from these values plus `@/onchain-facts`. Defaults are Arc Testnet and its USDC. The contract's USDC address is a constructor argument, so pointing at another network means changing the env values and redeploying. I'll only set up and deploy on Arc Testnet. A mainnet move is a separate step you take later, and it needs its own review and sign-off.
- **Wallet:** ConnectKit (default) on Arc Testnet. The connect button reads "Sign in".

### Files to Create/Modify
1. `contracts/FreelanceEscrow.sol` – the escrow contract described above.
2. `contracts/test/mocks/MockUSDC.sol` – 6-decimal test token with a blocklist switch, to prove one blocked address can't block anyone else.
3. `contracts/test/FreelanceEscrow.t.sol` – unit tests (listed under Done When).
4. `contracts/test/FreelanceEscrow.invariant.t.sol` – a random-action handler plus invariant tests for `deposited = paid + refunded + remaining` and for the global balance.
5. `src/lib/escrowAbi.ts` – contract ABI.
6. `src/lib/escrow.ts` – contract address (from `VITE_ESCROW_ADDRESS`), shared types and state-to-label mapping.
7. `src/lib/format.ts` – dollars via `@/onchain-money`, bps to percent, seconds to days and countdown text.
8. `src/hooks/useEscrow.ts` – read hooks for jobs and milestones, a write helper and a "my payout balance" read.
9. `src/hooks/useUsdcAllowance.ts` – checks and requests permission to move the funding amount.
10. `src/config.ts` – modify. Build the chain and RPC transport from the env values (Arc Testnet by default) and add the connectors ConnectKit needs. Add `src/lib/env.ts`, which validates the `VITE_*` values and fails with a readable message if one is missing or wrong.
11. `src/main.tsx` – modify. Add the wagmi, react-query and ConnectKit providers.
12. `src/App.tsx` – modify. Layout, top bar with sign-in, "My payouts" chip, and navigation between "My jobs", "New job" and a job's detail page.
13. `src/components/CreateJobForm.tsx` – set the job and total amount, freelancer, arbiter, and milestones with payees. Live check that milestone percentages sum to 100% and each payee split sums to 100%, plus a dollar breakdown per milestone.
14. `src/components/FundJobStep.tsx` – two-step "allow payment, then hold in escrow" flow with a clear summary.
15. `src/components/JobList.tsx` – the person's jobs with role badges and a "needs your action" hint.
16. `src/components/JobDetail.tsx` – job header, escrow summary (held, paid out, refunded) and the milestone timeline.
17. `src/components/MilestoneCard.tsx` – state, dollar amount, payees and shares, countdowns, and the right action buttons.
18. `src/components/actions/ClientActions.tsx` – approve, ask for changes, reject, open dispute, refund (when late), and "Get your money back" 7 days after a final rejection with no dispute.
19. `src/components/actions/FreelancerActions.tsx` – decline job (before the first start), start work (with arbiter acceptance note), deliver, open dispute (when allowed, with a countdown for the 7-day window).
20. `src/components/actions/ArbiterActions.tsx` – dispute resolver with a slider or amount for "return to client" and a live split preview.
21. `src/components/PayoutsPanel.tsx` – "Money available to you" with a Withdraw button.
22. `src/components/ui/` (`StatusBadge.tsx`, `TxButton.tsx`, `Countdown.tsx`) – shared pieces with plain-language pending, success and error states.
23. `.env` – add `VITE_CHAIN_ID`, `VITE_RPC_URL`, `VITE_USDC_ADDRESS` (public values only) and, after deploy, `VITE_ESCROW_ADDRESS`.

### Build Sequence
Contract and unit tests come first. The UI starts only once they pass.
1. Write `FreelanceEscrow.sol` to the rules above, including the final-rejection refund and `declineJob`.
2. Run a balanced security review of the contract and apply the fixes. Run static analysis and fix anything serious.
3. Write `MockUSDC` and the unit tests, including the per-job invariant `deposited = paid + refunded + remaining` under random actions, then run them. Fix any real contract bugs they uncover, then re-run.
4. Add the global balance invariant test last. If time runs short, drop it and keep the per-job one.
5. Deploy to Arc Testnet with the USDC address as the constructor argument. Save the address to `VITE_ESCROW_ADDRESS` and copy the ABI into `src/lib/escrowAbi.ts`.
6. Set up the env-driven config, providers and the app shell, with sign-in and chain handling.
7. Build the helpers, read hooks and shared UI pieces.
8. Build Create job and Fund job: the form with live percentage checks, the allow-payment step, then the funding step.
9. Build the job list, job detail (with the arbiter card) and milestone card with state-aware countdowns.
10. Build the client, freelancer and arbiter action panels and the payouts panel.
11. Walk through the full flow in the preview with test wallets: create and fund, decline, start, deliver, revise, approve, dispute and resolve, final rejection then refund, refund after a missed deadline, withdraw. Fix any UI or contract wiring issues.

### Done When
- [ ] You can create a job with multiple milestones and payees, and it is funded in full in one confirmed step.
- [ ] Creation fails with a clear message if milestone percentages don't total 100% or any milestone's payee shares don't total 100%. The tests cover both on the contract side.
- [ ] State transition tests cover every legal move and revert on every illegal one. This includes sequential gating, role checks (only the client, freelancer or arbiter for their own actions) and the freelancer's dispute right only after revisions are used up and a final rejection.
- [ ] Auto-approve tests: it reverts before `deliveredAt + reviewPeriod`, works for any caller at and after it, and is blocked after a final rejection.
- [ ] Dispute tests: the arbiter's split pays the right dollars to the client and by share to payees, including rounding, a 0% refund, a 100% refund and the 30-day timeout. Other milestones stay untouched, and only the arbiter can resolve.
- [ ] Missed-deadline refund tests work, and the client can't refund before the deadline.
- [ ] Final-rejection tests: the client can't refund before 7 days after the rejection, can refund the whole milestone after 7 days, and the freelancer can still dispute right up to that refund. A dispute opened before the refund blocks it.
- [ ] Decline tests: only the freelancer can decline, only before milestone 1 is started, the client's full deposit is credited back, and all milestones end Refunded. Declining after starting reverts.
- [ ] Changing `VITE_CHAIN_ID`, `VITE_RPC_URL` or `VITE_USDC_ADDRESS` is the only app change needed to point at another network. The app shows a readable error if one is missing.
- [ ] Pull-payment test: a blocked payee address can't stop other payees or the client from withdrawing.
- [ ] The per-job invariant `deposited = paid + refunded + remaining` holds after random sequences of actions. The global balance invariant (contract balance = unsettled amounts + unwithdrawn balances) is a stretch goal and is dropped first if time runs short. A check confirms the contract has no owner or admin function.
- [ ] Every state change emits its event, and the tests check them.
- [ ] The balanced security review and static analysis finish with no unresolved serious findings.
- [ ] The contract is deployed on Arc Testnet and the app reads and writes it using USDC.
- [ ] The UI shows dollars and plain-language states only. Clients, freelancers, payees and arbiters each see the right actions, and a payee can withdraw their money.

## Ready to build?
