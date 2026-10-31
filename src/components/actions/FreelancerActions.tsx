import { ActionButton } from '@/components/ui/ActionButton'
import { ConfirmAction } from '@/components/ui/ConfirmAction'
import { REJECTION_REFUND_DELAY } from '@/lib/escrow'
import { shortAddress, timeUntil, usd } from '@/lib/format'
import type { ActionProps } from './types'

export function FreelancerActions({ bundle, milestone: m, available, tx, now }: ActionProps) {
  const id = bundle.job.id
  const idx = BigInt(m.index)
  const { call, pending } = tx

  if (!['start', 'decline', 'deliver', 'freelancerDispute', 'acceptPartial'].some((k) => available.has(k as never))) {
    return null
  }

  return (
    <div className="space-y-3">
      {available.has('acceptPartial') && (
        <div className="rounded-2xl bg-[#fdf1d8] p-4">
          <p className="font-semibold text-[#8a5a00]">The client made a settlement offer</p>
          <p className="tabular mt-1 text-sm text-[var(--ink-2)]">
            If you accept, {usd(m.proposedRefund)} goes back to the client and {usd(m.amount - m.proposedRefund)} is paid to the team. This milestone is then finished. If you decline, nothing changes and the client can still approve in full.
          </p>
          <div className="mt-3 flex flex-wrap gap-2">
            <ConfirmAction
              id={`acceptpartial-${m.index}`}
              pending={pending}
              variant="primary"
              confirmLabel="Tap again to accept"
              onConfirm={() => void call(`acceptpartial-${m.index}`, 'acceptPartial', [id, idx, m.proposedRefund], 'Offer accepted. The money was split as offered.')}
            >
              Accept offer
            </ConfirmAction>
            <ActionButton id={`declinepartial-${m.index}`} variant="ghost" pending={pending} onClick={() => void call(`declinepartial-${m.index}`, 'declinePartial', [id, idx], 'Offer declined.')}>
              Decline offer
            </ActionButton>
          </div>
        </div>
      )}
      {available.has('start') && m.index === 0 && (
        <p className="rounded-2xl bg-[var(--surface-muted)] p-3 text-sm text-[var(--ink-2)]">
          By starting work you accept this job and its arbiter ({shortAddress(bundle.job.arbiter)}), who decides any disagreement.
        </p>
      )}
      <div className="flex flex-wrap gap-2">
        {available.has('start') && (
          <ActionButton id={`start-${m.index}`} pending={pending} onClick={() => void call(`start-${m.index}`, 'startMilestone', [id, idx], 'Work started. The delivery clock is running.')}>
            Start work
          </ActionButton>
        )}
        {available.has('decline') && (
          <ConfirmAction id="decline" pending={pending} onConfirm={() => void call('decline', 'declineJob', [id], 'You declined this job. The client gets everything back.')}>
            Decline this job
          </ConfirmAction>
        )}
        {available.has('deliver') && (
          <ActionButton id={`deliver-${m.index}`} pending={pending} onClick={() => void call(`deliver-${m.index}`, 'deliver', [id, idx], 'Delivered. The client can review it now.')}>
            {m.state === 4 ? 'Send updated work' : 'Mark as delivered'}
          </ActionButton>
        )}
        {available.has('freelancerDispute') && (
          <ConfirmAction id={`fdispute-${m.index}`} pending={pending} onConfirm={() => void call(`fdispute-${m.index}`, 'openDispute', [id, idx], 'Dispute opened. The arbiter will decide.')}>
            Open a dispute
          </ConfirmAction>
        )}
      </div>
      {available.has('freelancerDispute') && (
        <p className="text-xs text-[var(--muted)]">
          The client rejected this work. Open a dispute within {timeUntil(m.rejectedAt + REJECTION_REFUND_DELAY, now) === 'now' ? 'the next moments' : timeUntil(m.rejectedAt + REJECTION_REFUND_DELAY, now)}, or the client can take the money back.
        </p>
      )}
    </div>
  )
}
