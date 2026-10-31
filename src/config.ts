/**
 * wagmi configuration
 * Built with Arc Studio — https://studio.arc.io
 */

import { http, createConfig } from 'wagmi'
import { defineChain } from 'viem'
import { injected } from 'wagmi/connectors'
import { requireChain } from '@/onchain-facts'
import { CHAIN_ID, RPC_URL } from '@/lib/env'
import { registerChain } from './tracing'

const fact = requireChain(CHAIN_ID)

export const appChain = defineChain({
  id: CHAIN_ID,
  name: fact.name,
  nativeCurrency: {
    name: fact.nativeCurrency.symbol,
    symbol: fact.nativeCurrency.symbol,
    decimals: fact.nativeCurrency.decimals,
  },
  rpcUrls: { default: { http: [RPC_URL] } },
  blockExplorers: { default: { name: 'Explorer', url: fact.explorerBase } },
  testnet: fact.isTestnet,
})

// Pre-register chain RPC URLs so trace events show correct chain names immediately
registerChain(appChain.id, RPC_URL)

export const config = createConfig({
  chains: [appChain],
  connectors: [injected()],
  transports: {
    [appChain.id]: http(RPC_URL),
  },
})
