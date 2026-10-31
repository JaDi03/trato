import { ActionButton } from '@/components/ui/ActionButton'
import { ConfirmAction } from '@/components/ui/ConfirmAction'
import { timeUntil } from '@/lib/format'
import { PartialProposalPanel } from './PartialProposalPanel'
import type { ActionProps } from './types'

export function ClientActions({ bundle, milestone: m, available, tx, now }: ActionProps) {
  const id = bundle.job.id
  const idx = BigInt(m.index)
  const { call, pending } = tx
  const left = m.maxRevisions - m.revisionsUsed

  if (
    !['approve', 'proposePartial', 'revise', 'reject', 'clientDispute', 'refundLate', 'refundRejected'].some((k) =>
      available.has(k as never),
    )
  ) {
    return null
  }

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        {available.has('approve') && (
          <ActionButton id={`approve-${m.index}`} pending={pending} onClick={() => void call(`approve-${m.index}`, 'approve', [id, idx], 'Approved. The payment was released.')}>
            Approve and pay
          </ActionButton>
        )}
        {available.has('revise') && (
          <ActionButton id={`revise-${m.index}`} variant="ghost" pending={pending} onClick={() => void call(`revise-${m.index}`, 'requestRevision', [id, idx], 'Changes requested.')}>
            Ask for changes ({left} left)
          </ActionButton>
        )}
        {available.has('reject') && (
          <ConfirmAction id={`reject-${m.index}`} pending={pending} onConfirm={() => void call(`reject-${m.index}`, 'rejectDelivery', [id, idx], 'Delivery rejected.')}>
            Reject delivery
          </ConfirmAction>
        )}
        {available.has('clientDispute') && (
          <ConfirmAction id={`cdispute-${m.index}`} pending={pending} onConfirm={() => void call(`cdispute-${m.index}`, 'openDispute', [id, idx], 'Dispute opened. The arbiter will decide.')}>
            Open a dispute
          </ConfirmAction>
        )}
        {available.has('refundLate') && (
          <ConfirmAction id={`refund-${m.index}`} pending={pending} onConfirm={() => void call(`refund-${m.index}`, 'refundMilestone', [id, idx], 'The money for this milestone is back with you.')}>
            Get this money back
          </ConfirmAction>
        )}
        {available.has('refundRejected') && (
          <ConfirmAction id={`refundrej-${m.index}`} pending={pending} onConfirm={() => void call(`refundrej-${m.index}`, 'refundAfterRejection', [id, idx], 'The money for this milestone is back with you.')}>
            Get this money back
          </ConfirmAction>
        )}
      </div>
      <PartialProposalPanel bundle={bundle} milestone={m} available={available} tx={tx} now={now} />
      {m.state === 2 && !m.rejectedFinal && m.deliveredAt + m.reviewPeriod > now && (
        <p className="text-xs text-[var(--muted)]">
          If you do nothing, the payment is released automatically in {timeUntil(m.deliveredAt + m.reviewPeriod, now)}.
        </p>
      )}
    </div>
  )
}
