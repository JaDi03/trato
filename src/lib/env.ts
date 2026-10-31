import { isAddress, type Address } from 'viem'
import { getChain, getUsdc } from '@/onchain-facts'

/**
 * Deployment settings. Everything network-specific comes from VITE_* values so
 * pointing the app at another network is a config change plus a redeploy.
 */
const raw = import.meta.env as Record<string, string | undefined>

const DEFAULT_CHAIN_ID = 5042002 // Arc Testnet

const problems: string[] = []

const parsedChainId = raw.VITE_CHAIN_ID ? Number(raw.VITE_CHAIN_ID) : DEFAULT_CHAIN_ID
let chainId = parsedChainId
if (!Number.isInteger(parsedChainId) || !getChain(parsedChainId)) {
  problems.push('VITE_CHAIN_ID is missing or not a supported network.')
  chainId = DEFAULT_CHAIN_ID
}

const chainFact = getChain(chainId)

const rpcUrl = raw.VITE_RPC_URL || chainFact?.rpcUrls[0] || ''
if (!rpcUrl) problems.push('VITE_RPC_URL is missing.')

const usdcRaw = raw.VITE_USDC_ADDRESS || getUsdc(chainId)?.address || ''
if (!isAddress(usdcRaw)) problems.push('VITE_USDC_ADDRESS is missing or not a valid address.')

const escrowRaw = raw.VITE_ESCROW_ADDRESS || ''
if (!isAddress(escrowRaw)) problems.push('VITE_ESCROW_ADDRESS is missing or not a valid address.')

export const CHAIN_ID = chainId
export const RPC_URL = rpcUrl
export const USDC_ADDRESS = usdcRaw as Address
export const ESCROW_ADDRESS = escrowRaw as Address
export const ENV_PROBLEMS: readonly string[] = problems
