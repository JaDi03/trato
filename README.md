# Trato — Freelance Milestone Escrow on Arc

A decentralized freelance escrow platform paid in native USDC on Arc. Clients fund milestone-based contracts up front, funds are held securely in the escrow smart contract, and funds are released milestone by milestone as work is approved.

- **Live Application:** [https://trato-rho.vercel.app/](https://trato-rho.vercel.app/)
- **Built with:** [Arc Studio](https://studio.arc.io)
- **Verified Mainnet Contract:** [`0x9289Afd63C8802F5B6633a5821abC1B282F05D87`](https://explorer.arc.io/address/0x9289Afd63C8802F5B6633a5821abC1B282F05D87)

## Arc Mainnet Live Verification & USDC Proof of Movement

This project is deployed and verified on **Arc Mainnet (Chain ID 5042)** with real USDC moving through the smart contract and live application.

### End-to-End Lifecycle Proof (Job #1: $1.00 USDC)

| Action | Caller | Description | Transaction Explorer Link |
| :--- | :--- | :--- | :--- |
| **Contract Deployment** | Deployer | Deploy `FreelanceEscrow` with native USDC | [View Tx](https://explorer.arc.io/tx/0x728aa0a1152ebcacf0ed14d9bd762e769440938a2b461fa198609100b7dbe51e) |
| **Create & Fund Job** | Client (`0xe16E...`) | Deposit $1.00 USDC into escrow (2 milestones) | [View Tx](https://explorer.arc.io/tx/0xd9f610aeb82ff2cfb2ac0eaa559cf1c4514507e4f5b4db5a16b7df35cedbb823) |
| **Start Milestone 1** | Freelancer (`0x2B16...`) | Accept job terms & start delivery clock | [View Tx](https://explorer.arc.io/tx/0xc499e06a2743b78d3b0780cd0ad1ef071c99f06c48549cc465c54c843f39a6b3) |
| **Deliver Milestone 1** | Freelancer (`0x2B16...`) | Mark work delivered for client review | [View Tx](https://explorer.arc.io/tx/0xcf513773e746ff290e3350588f040160a0b3c306b691b1db852be87d2e6945a9) |
| **Approve & Split M1** | Client (`0xe16E...`) | Approve $0.60 USDC (70% Freelancer, 30% Collaborator) | [View Tx](https://explorer.arc.io/tx/0xb0735eae53f1fbec62479872e65dc1df047a036fd039f941a4e3d552995cf5d8) |
| **Start Milestone 2** | Freelancer (`0x2B16...`) | Unlock & start second milestone | [View Tx](https://explorer.arc.io/tx/0x8861242a2615088adc7fdd65950fe7ab3513f0260b75cb0a29ddd9aa251bd2e9) |
| **Deliver Milestone 2** | Freelancer (`0x2B16...`) | Mark second milestone delivered | [View Tx](https://explorer.arc.io/tx/0x3e9e38f217216b15968fd18378d8808355bdfdc871203e5eeb94701b2a8b5584) |
| **Approve & Complete M2**| Client (`0xe16E...`) | Approve $0.40 USDC & mark job finished | [View Tx](https://explorer.arc.io/tx/0x2827729e230f609540cf2ef31a988a286ba3f6a0da69ff234049f977b568281b) |
| **Withdraw (Freelancer)** | Freelancer (`0x2B16...`) | Claim total earnings ($0.82 USDC) | [View Tx](https://explorer.arc.io/tx/0xc6675d4a85957e6682bbacdc52b2bcdd3d8f21d302ecd6f65216685491ffcddc) |
| **Withdraw (Collaborator)**| Collaborator (`0x281A...`)| Claim team split earnings ($0.18 USDC) | [View Tx](https://explorer.arc.io/tx/0x19d1a4b198062bf9e67feb19d3aed5d1c7951916650cbff9a704ac410a5172ad) |

## What you can do

- **Sequential Milestones:** Start a job with up to 20 milestones, set each milestone's share, delivery duration, review period, and allowed revisions.
- **Multi-party Splits:** Split each milestone's payment between one or more team members or subcontractors.
- **Deliver & Review:** Approve work, request revisions, reject a delivery, or open a dispute.
- **Bilateral Partial Settlements:** Offer to pay for part of a delivered milestone and get the rest refunded without requiring an arbiter; money only moves when accepted by the freelancer.
- **Arbiter Dispute Resolution:** If an impasse occurs, an independent neutral arbiter decides how the disputed milestone is split. Remaining milestones proceed sequentially.
- **Missed Deadline Protection:** Full milestone refund options if work is late or unstarted after the grace window.
- **Pull Payments:** Isolated withdrawals so one blocked account cannot stop anyone else from claiming their earnings.

## Tech stack

- **Frontend:** React 18, Vite, TypeScript, Tailwind CSS
- **Web3 Integration:** wagmi, viem, ConnectKit
- **Smart Contracts:** Solidity 0.8.28 with Foundry (222 unit & invariant tests passing)
- **Deployment:** Vercel (Frontend) & Arc Mainnet (Contracts)

## Development

Prerequisites: [Bun](https://bun.sh) (or Node.js) and [Foundry](https://book.getfoundry.sh).

```bash
npm install
npm run dev            # start the app
npm run check          # lint and typecheck
npm run contracts:build
npm run contracts:test
```

### Environment variables

All values are public. Create a `.env` file with:

- `VITE_ESCROW_ADDRESS`: address of the deployed escrow contract (`0x9289Afd63C8802F5B6633a5821abC1B282F05D87`).
- `VITE_CHAIN_ID`: network ID (`5042` for Arc Mainnet).
- `VITE_RPC_URL`: network RPC endpoint (`https://rpc.mainnet.arc.io`).
- `VITE_USDC_ADDRESS`: USDC token address (`0x3600000000000000000000000000000000000000`).

Arc Testnet test deployment (chain 5042002, for reference only): `0xa3ad8bc91654afdac1e97d59fcb7c7c4e58d9713`.
