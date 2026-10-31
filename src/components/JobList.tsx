import { ChevronRight, Plus } from 'lucide-react'
import { useAccount } from 'wagmi'
import { PayoutsPanel } from '@/components/PayoutsPanel'
import { useMyJobs } from '@/hooks/useEscrow'
import type { Route } from '@/hooks/useRoute'
import { useNow } from '@/hooks/useTx'
import { availableActions, MState, ROLE_LABEL, rolesOf, type JobBundle } from '@/lib/escrow'
import { usd } from '@/lib/format'

function needsAttention(bundle: JobBundle, address: `0x${string}`, now: number): boolean {
  const roles = rolesOf(address, bundle)
  return bundle.milestones.some((m) => {
    const actions = availableActions(roles, bundle, m, now)
    actions.delete('autoApprove')
    actions.delete('timeout')
    return actions.size > 0
  })
}

export function JobList({ go }: { go: (route: Route) => void }) {
  const { address } = useAccount()
  const { data: jobs, isLoading } = useMyJobs(address)
  const now = useNow()

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="display text-3xl font-bold text-balance">Your jobs</h1>
          <p className="mt-1 text-[var(--muted)]">Jobs you started, work on, get paid from, or referee.</p>
        </div>
        <button type="button" className="btn btn-primary" onClick={() => go({ name: 'new' })}>
          <Plus className="h-4 w-4" aria-hidden /> New job
        </button>
      </div>

      <PayoutsPanel />

      {!address && (
        <div className="card p-8 text-center">
          <p className="display text-xl font-semibold">Sign in to see your jobs</p>
          <p className="mx-auto mt-1 max-w-sm text-sm text-[var(--muted)]">Use the Sign in button at the top. Your jobs and payouts show up here.</p>
        </div>
      )}

      {address && isLoading && <p className="text-[var(--muted)]">Loading your jobs...</p>}

      {address && jobs && jobs.length === 0 && (
        <div className="card p-8 text-center">
          <p className="display text-xl font-semibold">No jobs yet</p>
          <p className="mx-auto mt-1 max-w-sm text-sm text-[var(--muted)]">Start a job to hold the payment in escrow and pay out as work is approved.</p>
          <button type="button" className="btn btn-primary mt-4" onClick={() => go({ name: 'new' })}>Start a job</button>
        </div>
      )}

      <ul className="space-y-3">
        {jobs?.map((bundle) => {
          const { job, milestones } = bundle
          const roles = rolesOf(address, bundle)
          const done = milestones.filter((m) => m.state === MState.Paid || m.state === MState.Refunded).length
          const attention = address ? needsAttention(bundle, address, now) : false
          return (
            <li key={job.id.toString()}>
              <button type="button" onClick={() => go({ name: 'job', id: job.id })} className="card flex w-full items-center justify-between gap-3 p-5 text-left transition-colors hover:border-[var(--border-strong)]">
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="display text-lg font-semibold">Job #{job.id.toString()}</p>
                    {roles.map((r) => (
                      <span key={r} className="rounded-full bg-[var(--surface-muted)] px-2.5 py-0.5 text-xs font-semibold text-[var(--ink-2)]">{ROLE_LABEL[r]}</span>
                    ))}
                    {attention && <span className="rounded-full bg-[#fdf1d8] px-2.5 py-0.5 text-xs font-semibold text-[#8a5a00]">Needs your action</span>}
                  </div>
                  <p className="tabular mt-1 text-sm text-[var(--muted)]">
                    {usd(job.total)} total, {job.completed ? 'finished' : `${done} of ${milestones.length} milestones finished`}
                  </p>
                </div>
                <ChevronRight className="h-5 w-5 shrink-0 text-[var(--subtle)]" aria-hidden />
              </button>
            </li>
          )
        })}
      </ul>
    </div>
  )
}
