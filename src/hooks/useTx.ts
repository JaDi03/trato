import { useCallback, useEffect, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { useAccount, usePublicClient, useSwitchChain, useWriteContract } from 'wagmi'
import { erc20Abi, type Address } from 'viem'
import { escrowAbi } from '@/lib/escrowAbi'
import { CHAIN_ID, ESCROW_ADDRESS, USDC_ADDRESS } from '@/lib/env'
import { nowSeconds } from '@/lib/format'

const FRIENDLY: Array<[string, string]> = [
  ['User rejected', 'You cancelled the request.'],
  ['User denied', 'You cancelled the request.'],
  ['ReviewPeriodExpired', 'The review period has already ended.'],
  ['TooEarly', "It's too early to do that yet."],
  ['AlreadyRejected', 'This delivery was already rejected.'],
  ['RevisionsAvailable', 'The client can still ask for changes first.'],
  ['NothingToWithdraw', 'There is no money to withdraw right now.'],
  ['InvalidRefund', 'That refund has to be more than $0 and less than the whole milestone.'],
  ['ProposalMismatch', 'The client changed their offer. Review the new terms and try again.'],
  ['NoProposal', 'There is no open offer on this milestone.'],
  ['insufficient funds', 'Your account does not have enough USDC.'],
  ['exceeds balance', 'Your account does not have enough USDC.'],
  ['allowance', 'Payment has not been allowed yet.'],
]

export function friendlyError(error: unknown): string {
  const text = error instanceof Error ? `${error.message} ${(error as { shortMessage?: string }).shortMessage ?? ''}` : String(error)
  for (const [needle, message] of FRIENDLY) if (text.includes(needle)) return message
  return 'That did not go through. Please try again.'
}

interface SendOptions {
  key: string
  request: Record<string, unknown>
  success: string
}

/** Sends one action, waits for it to finish, refreshes data and shows plain-language feedback. */
export function useSend() {
  const { chainId } = useAccount()
  const { switchChainAsync } = useSwitchChain()
  const { writeContractAsync } = useWriteContract()
  const client = usePublicClient({ chainId: CHAIN_ID })
  const queryClient = useQueryClient()
  const [pending, setPending] = useState<string | null>(null)

  const send = useCallback(
    async ({ key, request, success }: SendOptions): Promise<boolean> => {
      setPending(key)
      try {
        if (chainId !== CHAIN_ID) await switchChainAsync({ chainId: CHAIN_ID })
        const hash = await writeContractAsync({ ...request, chainId: CHAIN_ID } as Parameters<
          typeof writeContractAsync
        >[0])
        const receipt = await client?.waitForTransactionReceipt({ hash })
        if (receipt?.status === 'reverted') throw new Error('Reverted')
        await queryClient.invalidateQueries({ queryKey: ['escrow'] })
        toast.success(success)
        return true
      } catch (error) {
        toast.error(friendlyError(error))
        return false
      } finally {
        setPending(null)
      }
    },
    [chainId, client, queryClient, switchChainAsync, writeContractAsync],
  )

  const call = useCallback(
    (key: string, functionName: string, args: readonly unknown[], success: string) =>
      send({ key, request: { address: ESCROW_ADDRESS, abi: escrowAbi, functionName, args }, success }),
    [send],
  )

  const allowSpending = useCallback(
    (amount: bigint) =>
      send({
        key: 'allow',
        request: { address: USDC_ADDRESS, abi: erc20Abi, functionName: 'approve', args: [ESCROW_ADDRESS, amount] as [Address, bigint] },
        success: 'Payment allowed. You can fund the job now.',
      }),
    [send],
  )

  return { send, call, allowSpending, pending }
}

/** Current time in unix seconds, refreshed on an interval. */
export function useNow(intervalMs = 5_000): number {
  const [now, setNow] = useState(nowSeconds())
  useEffect(() => {
    const id = setInterval(() => setNow(nowSeconds()), intervalMs)
    return () => clearInterval(id)
  }, [intervalMs])
  return now
}
