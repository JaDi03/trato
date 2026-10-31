import { Check, ShieldCheck } from 'lucide-react'
import { useAccount, usePublicClient } from 'wagmi'
import { ActionButton } from '@/components/ui/ActionButton'
import { useUsdcStanding } from '@/hooks/useEscrow'
import { useSend } from '@/hooks/useTx'
import { escrowAbi } from '@/lib/escrowAbi'
import { CHAIN_ID, ESCROW_ADDRESS } from '@/lib/env'
import { bpsToPercent, formatDuration, shortAddress, usd } from '@/lib/format'
import type { ValidationResult } from '@/lib/jobForm'

interface FundJobStepProps {
  result: ValidationResult
  amounts: bigint[]
  onBack: () => void
  onDone: (jobId: bigint | null) => void
}

export function FundJobStep({ result, amounts, onBack, onDone }: FundJobStepProps) {
  const { address } = useAccount()
  const client = usePublicClient({ chainId: CHAIN_ID })
  const { data: standing } = useUsdcStanding(address)
  const { send, allowSpending, pending } = useSend()

  const total = result.total ?? 0n
  const allowed = (standing?.allowance ?? 0n) >= total
  const hasFunds = (standing?.balance ?? 0n) >= total

  const fund = async () => {
    if (!result.freelancer || !result.arbiter || !result.milestones || !address) return
    const ok = await send({
      key: 'fund',
      request: {
        address: ESCROW_ADDRESS,
        abi: escrowAbi,
        functionName: 'createJob',
        args: [result.freelancer, result.arbiter, total, result.milestones],
      },
      success: 'Your payment is now held in escrow.',
    })
    if (!ok) return
    const ids = await client?.readContract({ address: ESCROW_ADDRESS, abi: escrowAbi, functionName: 'jobsOf', args: [address] })
    onDone(ids && ids.length > 0 ? ids[ids.length - 1] : null)
  }

  return (
    <div className="space-y-5">
      <div>
        <button type="button" onClick={onBack} className="text-sm font-semibold text-[var(--accent-hover)] hover:underline">
          Back to edit
        </button>
        <h1 className="display mt-2 text-3xl font-bold text-balance">Review and fund</h1>
        <p className="mt-1 text-[var(--muted)]">Check the details. Once funded, the money is held in escrow until you approve each milestone.</p>
      </div>

      <section className="card p-5">
        <p className="label">Payment held in escrow</p>
        <p className="display tabular text-4xl font-bold">{usd(total)}</p>
        <dl className="mt-4 grid gap-3 text-sm sm:grid-cols-2">
          <div>
            <dt className="text-[var(--muted)]">Freelancer</dt>
            <dd className="mono">{result.freelancer ? shortAddress(result.freelancer) : ''}</dd>
          </div>
          <div>
            <dt className="text-[var(--muted)]">Arbiter (decides disputes)</dt>
            <dd className="mono">{result.arbiter ? shortAddress(result.arbiter) : ''}</dd>
          </div>
        </dl>
      </section>

      <section className="card divide-y divide-[var(--border)]">
        {result.milestones?.map((m, i) => (
          <div key={i} className="flex flex-wrap items-center justify-between gap-2 p-4">
            <div>
              <p className="font-semibold">Milestone {i + 1}</p>
              <p className="text-sm text-[var(--muted)]">
                {bpsToPercent(m.bps)} of the job, {formatDuration(m.deliveryDuration)} to deliver, {formatDuration(m.reviewPeriod)} to review, {m.maxRevisions} {m.maxRevisions === 1 ? 'change' : 'changes'} allowed, paid to {m.payees.length} {m.payees.length === 1 ? 'person' : 'people'}
              </p>
            </div>
            <p className="display tabular text-lg font-semibold">{usd(amounts[i] ?? 0n)}</p>
          </div>
        ))}
      </section>

      <section className="card space-y-4 p-5">
        <div className="flex items-start gap-3">
          <span className={`mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-sm font-bold ${allowed ? 'bg-[#e1f3e8] text-[var(--success)]' : 'bg-[var(--surface-muted)]'}`}>
            {allowed ? <Check className="h-4 w-4" aria-hidden /> : '1'}
          </span>
          <div className="flex-1">
            <p className="font-semibold">Allow the payment</p>
            <p className="text-sm text-[var(--muted)]">Lets the escrow take {usd(total)} from your balance when you fund the job.</p>
            {!allowed && (
              <ActionButton id="allow" pending={pending} className="mt-3" disabled={!hasFunds} onClick={() => void allowSpending(total)}>
                Allow {usd(total)}
              </ActionButton>
            )}
          </div>
        </div>

        <div className="flex items-start gap-3">
          <span className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-[var(--surface-muted)] text-sm font-bold">2</span>
          <div className="flex-1">
            <p className="font-semibold">Hold the payment in escrow</p>
            <p className="text-sm text-[var(--muted)]">The full amount is locked in. Nobody can take it except by the rules above.</p>
            <ActionButton id="fund" pending={pending} className="mt-3" disabled={!allowed || !hasFunds} onClick={() => void fund()} busyLabel="Funding...">
              <ShieldCheck className="h-4 w-4" aria-hidden /> Fund {usd(total)}
            </ActionButton>
          </div>
        </div>

        {standing && !hasFunds && (
          <p role="alert" className="rounded-2xl bg-[#fbe3e8] p-3 text-sm text-[var(--danger)]">
            Your balance is {usd(standing.balance)}, but this job needs {usd(total)}. Use "Get test USDC" in the sidebar to add test money.
          </p>
        )}
      </section>
    </div>
  )
}
