import { useQuery } from '@tanstack/react-query'
import { erc20Abi, type Address, type PublicClient } from 'viem'
import { usePublicClient } from 'wagmi'
import { escrowAbi } from '@/lib/escrowAbi'
import { CHAIN_ID, ESCROW_ADDRESS, USDC_ADDRESS } from '@/lib/env'
import type { JobBundle, JobData, MilestoneData } from '@/lib/escrow'

const REFRESH_MS = 8_000

async function fetchBundle(client: PublicClient, jobId: bigint): Promise<JobBundle> {
  const j = await client.readContract({
    address: ESCROW_ADDRESS,
    abi: escrowAbi,
    functionName: 'getJob',
    args: [jobId],
  })
  const count = Number(j.milestoneCount)
  const milestones = await Promise.all(
    Array.from({ length: count }, async (_, index): Promise<MilestoneData> => {
      const m = await client.readContract({
        address: ESCROW_ADDRESS,
        abi: escrowAbi,
        functionName: 'getMilestone',
        args: [jobId, BigInt(index)],
      })
      return {
        index,
        amount: m.amount,
        bps: Number(m.bps),
        deliveryDuration: Number(m.deliveryDuration),
        reviewPeriod: Number(m.reviewPeriod),
        maxRevisions: Number(m.maxRevisions),
        revisionsUsed: Number(m.revisionsUsed),
        state: Number(m.state),
        unlockedAt: Number(m.unlockedAt),
        startedAt: Number(m.startedAt),
        deadline: Number(m.deadline),
        deliveredAt: Number(m.deliveredAt),
        rejectedFinal: m.rejectedFinal,
        rejectedAt: Number(m.rejectedAt),
        disputedAt: Number(m.disputedAt),
        payees: m.payees,
        shares: m.shares.map(Number),
        proposedRefund: m.proposedRefund,
      }
    }),
  )
  const job: JobData = {
    id: jobId,
    client: j.client,
    freelancer: j.freelancer,
    arbiter: j.arbiter,
    total: j.total,
    paid: j.paid,
    refunded: j.refunded,
    remaining: j.remaining,
    milestoneCount: count,
    completed: j.completed,
    createdAt: Number(j.createdAt),
  }
  return { job, milestones }
}

export function useJobBundle(jobId: bigint | undefined) {
  const client = usePublicClient({ chainId: CHAIN_ID })
  return useQuery({
    queryKey: ['escrow', 'job', jobId?.toString()],
    enabled: !!client && jobId !== undefined,
    refetchInterval: REFRESH_MS,
    queryFn: () => fetchBundle(client as PublicClient, jobId as bigint),
  })
}

export function useMyJobs(address: Address | undefined) {
  const client = usePublicClient({ chainId: CHAIN_ID })
  return useQuery({
    queryKey: ['escrow', 'mine', address],
    enabled: !!client && !!address,
    refetchInterval: REFRESH_MS,
    queryFn: async () => {
      const c = client as PublicClient
      const ids = await c.readContract({
        address: ESCROW_ADDRESS,
        abi: escrowAbi,
        functionName: 'jobsOf',
        args: [address as Address],
      })
      const newest = [...ids].reverse().slice(0, 50)
      return Promise.all(newest.map((id) => fetchBundle(c, id)))
    },
  })
}

/** Money the person can take out right now, in raw USDC. */
export function useAvailableToWithdraw(address: Address | undefined) {
  const client = usePublicClient({ chainId: CHAIN_ID })
  return useQuery({
    queryKey: ['escrow', 'claimable', address],
    enabled: !!client && !!address,
    refetchInterval: REFRESH_MS,
    queryFn: () =>
      (client as PublicClient).readContract({
        address: ESCROW_ADDRESS,
        abi: escrowAbi,
        functionName: 'claimable',
        args: [address as Address],
      }),
  })
}

/** USDC balance and how much the escrow is currently allowed to take. */
export function useUsdcStanding(address: Address | undefined) {
  const client = usePublicClient({ chainId: CHAIN_ID })
  return useQuery({
    queryKey: ['escrow', 'usdc', address],
    enabled: !!client && !!address,
    refetchInterval: REFRESH_MS,
    queryFn: async () => {
      const c = client as PublicClient
      const [balance, allowance] = await Promise.all([
        c.readContract({ address: USDC_ADDRESS, abi: erc20Abi, functionName: 'balanceOf', args: [address as Address] }),
        c.readContract({
          address: USDC_ADDRESS,
          abi: erc20Abi,
          functionName: 'allowance',
          args: [address as Address, ESCROW_ADDRESS],
        }),
      ])
      return { balance, allowance }
    },
  })
}
