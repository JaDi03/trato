import { useState } from 'react'
import { ActionButton } from '@/components/ui/ActionButton'
import { parseDollars, usd } from '@/lib/format'
import type { ActionProps } from './types'

export function ArbiterActions({ bundle, milestone: m, available, tx }: ActionProps) {
  const [refund, setRefund] = useState('0')
  if (!available.has('resolve')) return null

  const parsed = parseDollars(refund)
  const valid = parsed !== null && parsed <= m.amount
  const clientGets = valid ? parsed : 0n
  const payeesGet = m.amount - clientGets

  const quick = (numerator: bigint) => {
    const value = (m.amount * numerator) / 100n
    setRefund(usd(value).replace(/[$,]/g, ''))
  }

  return (
    <div className="rounded-2xl bg-[var(--surface-muted)] p-4">
      <p className="font-semibold">Decide this dispute</p>
      <p className="text-sm text-[var(--muted)]">Choose how much of {usd(m.amount)} goes back to the client. The rest is paid to the people on this milestone by their shares.</p>

      <div className="mt-3 flex flex-wrap items-end gap-3">
        <div className="w-40">
          <label className="label" htmlFor={`refund-${m.index}`}>Back to client</label>
          <div className="relative">
            <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[var(--muted)]">$</span>
            <input id={`refund-${m.index}`} className="field tabular pl-7" inputMode="decimal" value={refund} onChange={(e) => setRefund(e.target.value)} />
          </div>
        </div>
        <div className="flex gap-2">
          {[0n, 50n, 100n].map((pct) => (
            <button key={pct.toString()} type="button" className="btn btn-ghost px-4" onClick={() => quick(pct)}>
              {pct.toString()}%
            </button>
          ))}
        </div>
      </div>

      <dl className="tabular mt-3 grid grid-cols-2 gap-2 text-sm">
        <div className="rounded-xl bg-white/70 p-3">
          <dt className="text-[var(--muted)]">Client gets</dt>
          <dd className="font-semibold">{usd(clientGets)}</dd>
        </div>
        <div className="rounded-xl bg-white/70 p-3">
          <dt className="text-[var(--muted)]">Freelancer and payees get</dt>
          <dd className="font-semibold">{usd(payeesGet)}</dd>
        </div>
      </dl>

      {!valid && <p role="alert" className="mt-2 text-sm text-[var(--danger)]">Enter an amount between $0 and {usd(m.amount)}.</p>}

      <ActionButton
        id={`resolve-${m.index}`}
        pending={tx.pending}
        className="mt-3"
        disabled={!valid}
        onClick={() => void tx.call(`resolve-${m.index}`, 'resolveDispute', [bundle.job.id, BigInt(m.index), clientGets], 'Dispute decided. The money has been assigned.')}
      >
        Confirm decision
      </ActionButton>
    </div>
  )
}
