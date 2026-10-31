import clsx from 'clsx'
import { Plus, Trash2 } from 'lucide-react'
import { bpsToPercent, usd } from '@/lib/format'
import {
  MAX_PAYEES,
  newPayee,
  payeeBpsTotal,
  percentToBps,
  type MilestoneDraft,
  type PayeeDraft,
} from '@/lib/jobForm'

interface MilestoneEditorProps {
  index: number
  draft: MilestoneDraft
  amount: bigint | null
  freelancer: string
  canRemove: boolean
  onChange: (next: MilestoneDraft) => void
  onRemove: () => void
}

export function MilestoneEditor({ index, draft, amount, freelancer, canRemove, onChange, onRemove }: MilestoneEditorProps) {
  const set = <K extends keyof MilestoneDraft>(key: K, value: MilestoneDraft[K]) => onChange({ ...draft, [key]: value })

  const setPayee = (key: string, patch: Partial<PayeeDraft>) =>
    set('payees', draft.payees.map((p) => (p.key === key ? { ...p, ...patch } : p)))

  const payeeTotal = payeeBpsTotal(draft)
  const payeesOk = payeeTotal === 10_000

  return (
    <section className="card p-5" aria-label={`Milestone ${index + 1}`}>
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="display text-lg font-semibold">Milestone {index + 1}</h3>
          <p className="tabular text-sm text-[var(--muted)]">{amount !== null ? `${usd(amount)} released when approved` : 'Enter the job total to see the amount'}</p>
        </div>
        {canRemove && (
          <button type="button" onClick={onRemove} className="btn btn-ghost px-3" aria-label={`Remove milestone ${index + 1}`}>
            <Trash2 className="h-4 w-4" aria-hidden />
          </button>
        )}
      </div>

      <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
        <div>
          <label className="label" htmlFor={`pct-${draft.key}`}>Share of job</label>
          <div className="relative">
            <input id={`pct-${draft.key}`} className="field tabular pr-8" inputMode="decimal" value={draft.percent} onChange={(e) => set('percent', e.target.value)} />
            <span className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2 text-[var(--muted)]">%</span>
          </div>
        </div>
        <div>
          <label className="label" htmlFor={`del-${draft.key}`}>Days to deliver</label>
          <input id={`del-${draft.key}`} className="field tabular" inputMode="decimal" value={draft.deliveryDays} onChange={(e) => set('deliveryDays', e.target.value)} />
        </div>
        <div>
          <label className="label" htmlFor={`rev-${draft.key}`}>Days to review</label>
          <input id={`rev-${draft.key}`} className="field tabular" inputMode="decimal" value={draft.reviewDays} onChange={(e) => set('reviewDays', e.target.value)} />
        </div>
        <div>
          <label className="label" htmlFor={`chg-${draft.key}`}>Changes allowed</label>
          <input id={`chg-${draft.key}`} className="field tabular" inputMode="numeric" value={draft.revisions} onChange={(e) => set('revisions', e.target.value)} />
        </div>
      </div>

      <div className="mt-5 rounded-2xl bg-[var(--surface-muted)] p-4">
        <div className="flex items-center justify-between">
          <p className="text-sm font-semibold">Who gets paid</p>
          <p className={clsx('tabular text-xs font-semibold', payeesOk ? 'text-[var(--success)]' : 'text-[var(--danger)]')}>
            {payeesOk ? 'Adds up to 100%' : `Adds up to ${bpsToPercent(payeeTotal)}, needs 100%`}
          </p>
        </div>

        <div className="mt-3 space-y-3">
          {draft.payees.map((p, i) => {
            const bps = percentToBps(p.percent)
            const share = amount !== null && bps !== null ? usd((amount * BigInt(bps)) / 10_000n) : null
            return (
              <div key={p.key} className="grid grid-cols-[1fr_88px_auto] items-end gap-2">
                <div>
                  <label className="label" htmlFor={`pa-${p.key}`}>Account ID {i + 1}</label>
                  <input id={`pa-${p.key}`} className="field mono text-sm" placeholder="0x..." value={p.address} onChange={(e) => setPayee(p.key, { address: e.target.value.trim() })} />
                </div>
                <div>
                  <label className="label" htmlFor={`ps-${p.key}`}>Share</label>
                  <input id={`ps-${p.key}`} className="field tabular" inputMode="decimal" value={p.percent} onChange={(e) => setPayee(p.key, { percent: e.target.value })} />
                </div>
                <button
                  type="button"
                  className="btn btn-ghost px-3"
                  aria-label={`Remove payee ${i + 1}`}
                  disabled={draft.payees.length === 1}
                  onClick={() => set('payees', draft.payees.filter((x) => x.key !== p.key))}
                >
                  <Trash2 className="h-4 w-4" aria-hidden />
                </button>
                <div className="col-span-3 -mt-1 flex items-center justify-between text-xs text-[var(--muted)]">
                  <button type="button" className="font-semibold text-[var(--accent-hover)] underline-offset-2 hover:underline disabled:opacity-40" disabled={!freelancer} onClick={() => setPayee(p.key, { address: freelancer })}>
                    Pay the freelancer
                  </button>
                  {share && <span className="tabular">{share}</span>}
                </div>
              </div>
            )
          })}
        </div>

        {draft.payees.length < MAX_PAYEES && (
          <button type="button" className="btn btn-ghost mt-3" onClick={() => set('payees', [...draft.payees, newPayee('', '0')])}>
            <Plus className="h-4 w-4" aria-hidden /> Add another person
          </button>
        )}
      </div>
    </section>
  )
}
