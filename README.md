# Freelance Escrow

A freelance escrow app paid in USDC. A client funds a whole job up front, the money is held in escrow, and it is released milestone by milestone as work is approved. Freelancers, the people who get paid, and a neutral arbiter each see only the actions that apply to them.

Built with [Arc Studio](https://studio.arc.io)

## What you can do

- Start a job with several milestones, set each milestone's share, delivery time, review time and number of allowed changes.
- Split each milestone's payment between one or more people.
- Approve work, ask for changes, reject a delivery, or open a dispute.
- Offer to pay for part of a delivered milestone and get the rest back. The freelancer accepts or declines, and nothing is paid until they accept.
- Get the money back for a milestone when a deadline is missed or a rejected delivery goes unanswered.
- Let a freelancer decline a job before starting the first milestone.
- Let an arbiter decide how a disputed milestone is split. Other milestones keep going.
- Withdraw your own earnings or refunds at any time.

## Tech stack

- React, Vite, TypeScript, Tailwind CSS
- wagmi, viem, ConnectKit
- Solidity 0.8.28 with Foundry

## Development

Prerequisites: [Bun](https://bun.sh) and [Foundry](https://book.getfoundry.sh).

```bash
bun install
bun run dev            # start the app
bun run check          # lint and typecheck
bun run contracts:build
bun run contracts:test
```

### Environment variables

All values are public. Create a `.env` file with:

- `VITE_ESCROW_ADDRESS`: address of the deployed escrow contract (required).
- `VITE_CHAIN_ID`: network to use. Defaults to Arc Testnet (5042002).
- `VITE_RPC_URL`: network RPC endpoint. Defaults to the network's public endpoint.
- `VITE_USDC_ADDRESS`: USDC token address. Defaults to the network's USDC.

`.env.example` holds the Arc mainnet values (chain 5042). The repo's `.env` points at Arc mainnet.

Arc mainnet deployment (chain 5042): `0x9289Afd63C8802F5B6633a5821abC1B282F05D87`, deployment transaction `0x728aa0a1152ebcacf0ed14d9bd762e769440938a2b461fa198609100b7dbe51e`. View it on https://explorer.arc.io/address/0x9289Afd63C8802F5B6633a5821abC1B282F05D87.

Arc Testnet test deployment (chain 5042002, for reference only): `0xa3ad8bc91654afdac1e97d59fcb7c7c4e58d9713`.

To point the app at another network, change these values and deploy the contract there with that network's USDC address as its constructor argument.

## Deploying to Arc mainnet

Mainnet moves real USDC and cannot be undone. Get an independent professional audit first, and deploy from your own wallet.

1. Fund your deployer wallet with real USDC on Arc mainnet. Gas on Arc is paid in USDC.
2. Store the deployer key in an encrypted Foundry keystore (once): `cast wallet import arc-deployer --interactive`.
3. Deploy, passing Arc mainnet USDC as the constructor argument:

   ```bash
   forge create contracts/FreelanceEscrow.sol:FreelanceEscrow \
     --rpc-url https://rpc.mainnet.arc.io \
     --account arc-deployer \
     --broadcast \
     --constructor-args 0x3600000000000000000000000000000000000000
   ```

4. Confirm the contract points at USDC: `cast call <DEPLOYED_ADDRESS> "usdc()(address)" --rpc-url https://rpc.mainnet.arc.io`. It must print `0x3600000000000000000000000000000000000000`.
5. Check the address on https://explorer.arc.io, then set `VITE_ESCROW_ADDRESS=<DEPLOYED_ADDRESS>` in `.env` (and in your hosting provider's environment settings) and restart or rebuild the app.
