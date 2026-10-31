import { ArrowLeft, Gavel } from 'lucide-react'
import { useAccount } from 'wagmi'
import { MilestoneCard } from '@/components/MilestoneCard'
import { useJobBundle } from '@/hooks/useEscrow'
import type { Route } from '@/hooks/useRoute'
import { useNow } from '@/hooks/useTx'
import { ROLE_LABEL, rolesOf } from '@/lib/escrow'
import { shortAddress, usd } from '@/lib/format'

export function JobDetail({ jobId, go }: { jobId: bigint; go: (route: Route) => void }) {
  const { address } = useAccount()
  const { data: bundle, isLoading, isError } = useJobBundle(jobId)
  const now = useNow()

  const back = (
    <button type="button" onClick={() => go({ name: 'jobs' })} className="inline-flex min-h-[44px] items-center gap-1 text-sm font-semibold text-[var(--accent-hover)] hover:underline">
      <ArrowLeft className="h-4 w-4" aria-hidden /> My jobs
    </button>
  )

  if (isLoading) return <div>{back}<p className="mt-4 text-[var(--muted)]">Loading job...</p></div>
  if (isError || !bundle) {
    return <div>{back}<p role="alert" className="mt-4 text-[var(--danger)]">We could not find job #{jobId.toString()}.</p></div>
  }

  const { job, milestones } = bundle
  const roles = rolesOf(address, bundle)
  const paidMilestones = milestones.filter((m) => m.state === 6 || m.state === 7).length

  const stat = (label: string, value: bigint) => (
    <div className="rounded-2xl bg-[var(--surface-muted)] p-4">
      <dt className="text-xs font-semibold uppercase tracking-[0.06em] text-[var(--muted)]">{label}</dt>
      <dd className="display tabular mt-1 text-xl font-bold">{usd(value)}</dd>
    </div>
  )

  return (
    <div className="space-y-5">
      {back}
      <div>
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="display text-3xl font-bold">Job #{job.id.toString()}</h1>
          {roles.map((r) => (
            <span key={r} className="rounded-full bg-[var(--accent)] px-3 py-1 text-xs font-semibold text-white">You: {ROLE_LABEL[r]}</span>
          ))}
        </div>
        <p className="mt-1 text-[var(--muted)]">
          {job.completed ? 'This job is finished.' : `${paidMilestones} of ${milestones.length} milestones finished.`} Total {usd(job.total)}.
        </p>
      </div>

      <section className="card p-5">
        <p className="label">Payment held in escrow</p>
        <p className="display tabular text-4xl font-bold">{usd(job.remaining)}</p>
        <dl className="mt-4 grid grid-cols-2 gap-3">
          {stat('Paid out', job.paid)}
          {stat('Returned to client', job.refunded)}
        </dl>
        <dl className="mt-4 grid gap-3 text-sm sm:grid-cols-2">
          <div>
            <dt className="text-[var(--muted)]">Client</dt>
            <dd className="mono">{shortAddress(job.client)}</dd>
          </div>
          <div>
            <dt className="text-[var(--muted)]">Freelancer</dt>
            <dd className="mono">{shortAddress(job.freelancer)}</dd>
          </div>
        </dl>
      </section>

      <section className="card flex items-start gap-3 p-5">
        <Gavel className="mt-0.5 h-5 w-5 shrink-0 text-[var(--accent-hover)]" aria-hidden />
        <div>
          <p className="font-semibold">Disputes are decided by {shortAddress(job.arbiter)}</p>
          <p className="text-sm text-[var(--muted)]">
            If the client and freelancer disagree, this neutral arbiter decides how a milestone's money is split. The freelancer accepts them by starting work. Only the disputed milestone is frozen.
          </p>
        </div>
      </section>

      <div className="space-y-4">
        {milestones.map((m) => (
          <MilestoneCard key={m.index} bundle={bundle} milestone={m} roles={roles} now={now} signedIn={!!address} />
        ))}
      </div>
    </div>
  )
}
