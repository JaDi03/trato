import clsx from 'clsx'
import { Plus } from 'lucide-react'
import { useMemo, useState } from 'react'
import { isAddress } from 'viem'
import { useAccount } from 'wagmi'
import { FundJobStep } from '@/components/FundJobStep'
import { MilestoneEditor } from '@/components/MilestoneEditor'
import type { Route } from '@/hooks/useRoute'
import { bpsToPercent, parseDollars, sameAddress, usd } from '@/lib/format'
import {
  emptyDraft,
  MAX_MILESTONES,
  milestoneAmounts,
  milestoneBpsTotal,
  newMilestone,
  validateDraft,
  type JobDraft,
  type MilestoneDraft,
  type ValidationResult,
} from '@/lib/jobForm'

export function CreateJobForm({ go }: { go: (route: Route) => void }) {
  const { address } = useAccount()
  const [draft, setDraft] = useState<JobDraft>(emptyDraft)
  const [checked, setChecked] = useState<ValidationResult | null>(null)
  const [errors, setErrors] = useState<string[]>([])

  const total = useMemo(() => parseDollars(draft.total), [draft.total])
  const amounts = useMemo(() => (total !== null && total > 0n ? milestoneAmounts(total, draft) : null), [total, draft])
  const bpsTotal = milestoneBpsTotal(draft)

  const update = (patch: Partial<JobDraft>) => setDraft((d) => ({ ...d, ...patch }))
  const updateMilestone = (key: string, next: MilestoneDraft) =>
    setDraft((d) => ({ ...d, milestones: d.milestones.map((m) => (m.key === key ? next : m)) }))

  /**
   * Keeps the first payee of each milestone in step with the freelancer: it is filled when empty,
   * and follows the freelancer when it still holds the previously typed freelancer address.
   * Only complete, valid addresses are copied, so half-typed text never lands in a payee field.
   */
  const setFreelancer = (value: string) => {
    setDraft((d) => {
      const previous = d.freelancer
      const fill = isAddress(value)
      return {
        ...d,
        freelancer: value,
        milestones: fill
          ? d.milestones.map((m) => {
              const [first, ...rest] = m.payees
              if (!first) return m
              const empty = first.address === ''
              const followsFreelancer = previous !== '' && sameAddress(first.address, previous)
              return empty || followsFreelancer
                ? { ...m, payees: [{ ...first, address: value }, ...rest] }
                : m
            })
          : d.milestones,
      }
    })
  }

  const addMilestone = () =>
    setDraft((d) => {
      const next = newMilestone('0')
      if (isAddress(d.freelancer) && next.payees[0]) next.payees[0].address = d.freelancer
      return { ...d, milestones: [...d.milestones, next] }
    })

  const review = () => {
    const result = validateDraft(draft)
    const problems = [...result.errors]
    if (address) {
      if (sameAddress(address, draft.freelancer)) problems.push('You cannot be the freelancer on your own job.')
      if (sameAddress(address, draft.arbiter)) problems.push('You cannot be the arbiter on your own job.')
      if (draft.milestones.some((m) => m.payees.some((p) => sameAddress(p.address, address)))) {
        problems.push('You cannot be paid on your own job.')
      }
    }
    setErrors(problems)
    setChecked(problems.length === 0 ? result : null)
  }

  if (checked && address) {
    return (
      <FundJobStep
        result={checked}
        amounts={amounts ?? []}
        onBack={() => setChecked(null)}
        onDone={(id) => (id ? go({ name: 'job', id }) : go({ name: 'jobs' }))}
      />
    )
  }

  return (
    <div className="space-y-5">
      <div>
        <h1 className="display text-3xl font-bold text-balance">Start a job</h1>
        <p className="mt-1 max-w-prose text-pretty text-[var(--muted)]">
          You put the full payment in escrow up front. It is released milestone by milestone as you approve the work.
        </p>
      </div>

      <section className="card space-y-4 p-5">
        <div>
          <label className="label" htmlFor="total">Total job amount</label>
          <div className="relative">
            <span className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 text-xl text-[var(--muted)]">$</span>
            <input id="total" className="field display tabular pl-9 text-2xl font-semibold" inputMode="decimal" placeholder="0.00" value={draft.total} onChange={(e) => update({ total: e.target.value })} />
          </div>
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <div>
            <label className="label" htmlFor="freelancer">Freelancer's account ID</label>
            <input id="freelancer" className="field mono text-sm" placeholder="0x..." value={draft.freelancer} onChange={(e) => setFreelancer(e.target.value.trim())} />
            <p className="mt-1 text-xs text-[var(--muted)]">The person who will start and deliver the work.</p>
          </div>
          <div>
            <label className="label" htmlFor="arbiter">Arbiter's account ID</label>
            <input id="arbiter" className="field mono text-sm" placeholder="0x..." value={draft.arbiter} onChange={(e) => update({ arbiter: e.target.value.trim() })} />
            <p className="mt-1 text-xs text-[var(--muted)]">A neutral person who decides if you and the freelancer disagree. The freelancer accepts them by starting work.</p>
          </div>
        </div>
      </section>

      <div className="flex items-center justify-between px-1">
        <h2 className="display text-xl font-semibold">Milestones</h2>
        <p className={clsx('tabular text-sm font-semibold', bpsTotal === 10_000 ? 'text-[var(--success)]' : 'text-[var(--danger)]')}>
          {bpsTotal === 10_000 ? 'Adds up to 100%' : `Adds up to ${bpsToPercent(bpsTotal)}, needs 100%`}
        </p>
      </div>

      {draft.milestones.map((m, i) => (
        <MilestoneEditor
          key={m.key}
          index={i}
          draft={m}
          amount={amounts ? amounts[i] ?? null : null}
          freelancer={draft.freelancer}
          canRemove={draft.milestones.length > 1}
          onChange={(next) => updateMilestone(m.key, next)}
          onRemove={() => update({ milestones: draft.milestones.filter((x) => x.key !== m.key) })}
        />
      ))}

      {draft.milestones.length < MAX_MILESTONES && (
        <button type="button" className="btn btn-ghost w-full" onClick={addMilestone}>
          <Plus className="h-4 w-4" aria-hidden /> Add a milestone
        </button>
      )}

      {errors.length > 0 && (
        <div role="alert" className="card border-[rgba(186,43,76,0.35)] p-4 text-sm">
          <p className="font-semibold text-[var(--danger)]">Fix these before continuing</p>
          <ul className="mt-1 list-disc pl-5 text-[var(--ink-2)]">
            {errors.map((e) => (
              <li key={e}>{e}</li>
            ))}
          </ul>
        </div>
      )}

      <div className="card flex flex-wrap items-center justify-between gap-3 p-5">
        <div>
          <p className="label mb-0">To be held in escrow</p>
          <p className="display tabular text-2xl font-bold">{total !== null ? usd(total) : '$0.00'}</p>
        </div>
        <button type="button" className="btn btn-primary" disabled={!address} onClick={review}>
          {address ? 'Review and fund' : 'Sign in to continue'}
        </button>
      </div>
    </div>
  )
}
