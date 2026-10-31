import { useState } from 'react'
import { ActionButton } from '@/components/ui/ActionButton'
import { parseDollars, usd } from '@/lib/format'
import type { ActionProps } from './types'

/** Client offers to pay for part of a delivered milestone. The freelancer must accept before any money moves. */
export function PartialProposalPanel({ bundle, milestone: m, available, tx }: ActionProps) {
  const [open, setOpen] = useState(false)
  const [refund, setRefund] = useState('')
  const { call, pending } = tx

  const canPropose = available.has('proposePartial')
  const hasOffer = m.proposedRefund > 0n
  if (!canPropose && !hasOffer) return null

  const parsed = parseDollars(refund)
  const valid = parsed !== null && parsed > 0n && parsed < m.amount
  const backToYou = valid ? parsed : 0n
  const toPayees = m.amount - backToYou
  const id = bundle.job.id
  const idx = BigInt(m.index)

  return (
    <div className="rounded-2xl bg-[var(--surface-muted)] p-4">
      {hasOffer && (
        <div className="mb-3">
          <p className="font-semibold">Your offer is waiting for the freelancer</p>
          <p className="tabular text-sm text-[var(--ink-2)]">
            {usd(m.proposedRefund)} back to you, {usd(m.amount - m.proposedRefund)} paid to the team. Nothing is paid until the freelancer accepts.
          </p>
          {available.has('cancelPartial') && (
            <ActionButton
              id={`cancelpartial-${m.index}`}
              pending={pending}
              variant="ghost"
              className="mt-2"
              onClick={() => void call(`cancelpartial-${m.index}`, 'cancelPartial', [id, idx], 'Your offer was withdrawn.')}
            >
              Withdraw my offer
            </ActionButton>
          )}
        </div>
      )}

      {canPropose && !open && (
        <button type="button" className="btn btn-ghost" onClick={() => setOpen(true)}>
          {hasOffer ? 'Change my offer' : 'Partial approve and refund'}
        </button>
      )}

      {canPropose && open && (
        <div>
          <p className="font-semibold">Offer a partial refund</p>
          <p className="text-sm text-[var(--muted)]">
            Pay for part of this milestone and get the rest back. The freelancer can accept or decline, and you can still approve in full or open a dispute meanwhile.
          </p>

          <div className="mt-3 w-44">
            <label className="label" htmlFor={`partial-${m.index}`}>Back to you</label>
            <div className="relative">
              <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-[var(--muted)]">$</span>
              <input id={`partial-${m.index}`} className="field tabular pl-7" inputMode="decimal" placeholder="0.00" value={refund} onChange={(e) => setRefund(e.target.value)} />
            </div>
          </div>

          <dl className="tabular mt-3 grid grid-cols-2 gap-2 text-sm">
            <div className="rounded-xl bg-white/70 p-3">
              <dt className="text-[var(--muted)]">Back to you</dt>
              <dd className="font-semibold">{usd(backToYou)}</dd>
            </div>
            <div className="rounded-xl bg-white/70 p-3">
              <dt className="text-[var(--muted)]">Paid to payees</dt>
              <dd className="font-semibold">{usd(toPayees)}</dd>
            </div>
          </dl>

          {refund !== '' && !valid && (
            <p role="alert" className="mt-2 text-sm text-[var(--danger)]">
              Enter an amount above $0 and below {usd(m.amount)}. To refund everything, use the reject or dispute options instead.
            </p>
          )}

          <div className="mt-3 flex flex-wrap gap-2">
            <ActionButton
              id={`propose-${m.index}`}
              pending={pending}
              disabled={!valid}
              busyLabel="Sending offer..."
              onClick={() => {
                if (parsed === null) return
                void call(`propose-${m.index}`, 'proposePartial', [id, idx, parsed], 'Offer sent. The freelancer can accept or decline.').then((ok) => {
                  if (ok) {
                    setOpen(false)
                    setRefund('')
                  }
                })
              }}
            >
              Send offer
            </ActionButton>
            <button type="button" className="btn btn-ghost" onClick={() => setOpen(false)}>Close</button>
          </div>
        </div>
      )}
    </div>
  )
}
