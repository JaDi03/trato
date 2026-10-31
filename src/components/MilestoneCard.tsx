import { ArbiterActions } from '@/components/actions/ArbiterActions'
import { ClientActions } from '@/components/actions/ClientActions'
import { FreelancerActions } from '@/components/actions/FreelancerActions'
import { ActionButton } from '@/components/ui/ActionButton'
import { StatusBadge } from '@/components/ui/StatusBadge'
import { useSend } from '@/hooks/useTx'
import {
  availableActions,
  DISPUTE_TIMEOUT,
  MState,
  REJECTION_REFUND_DELAY,
  START_WINDOW,
  statusOf,
  type JobBundle,
  type MilestoneData,
  type Role,
} from '@/lib/escrow'
import { bpsToPercent, formatDuration, shortAddress, timeUntil, usd } from '@/lib/format'

interface MilestoneCardProps {
  bundle: JobBundle
  milestone: MilestoneData
  roles: Role[]
  now: number
  signedIn: boolean
}

/** One plain sentence about what is happening and who needs to act. */
function whatsNext(m: MilestoneData, now: number): string | null {
  const reviewEnd = m.deliveredAt + m.reviewPeriod
  switch (m.state) {
    case MState.Pending:
      return m.unlockedAt > 0
        ? `Waiting for the freelancer to start. The client can take this money back after ${formatDuration(START_WINDOW)} without a start.`
        : 'Starts after the earlier milestone is finished.'
    case MState.InProgress:
      return now > m.deadline
        ? 'The delivery date has passed. The client can take this money back unless work arrives first.'
        : `Due in ${timeUntil(m.deadline, now)}.`
    case MState.InRevision:
      return now > m.deadline
        ? 'The delivery date has passed. The client can take this money back unless updated work arrives first.'
        : `Updated work is due in ${timeUntil(m.deadline, now)}.`
    case MState.Delivered:
      if (m.rejectedFinal) {
        return `The client rejected the work. The freelancer can open a dispute for ${timeUntil(m.rejectedAt + REJECTION_REFUND_DELAY, now)} more, then the client can take the money back.`
      }
      if (m.proposedRefund > 0n) {
        return `The client offered to settle this milestone with ${usd(m.proposedRefund)} back to them. Nothing is paid unless the freelancer accepts.`
      }
      return now < reviewEnd
        ? `The client has ${timeUntil(reviewEnd, now)} to review. After that anyone can release the payment.`
        : 'The review time is over. Anyone can release the payment now.'
    case MState.Disputed:
      return `The arbiter decides how to split this money. If nobody decides within ${formatDuration(DISPUTE_TIMEOUT)}, anyone can split it 50/50.`
    default:
      return null
  }
}

export function MilestoneCard({ bundle, milestone: m, roles, now, signedIn }: MilestoneCardProps) {
  const tx = useSend()
  const status = statusOf(m)
  const available = availableActions(roles, bundle, m, now)
  const props = { bundle, milestone: m, available, tx, now }
  const next = whatsNext(m, now)
  const settled = m.state === MState.Paid || m.state === MState.Refunded

  return (
    <article className="card p-5" aria-label={`Milestone ${m.index + 1}`}>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="label mb-1">Milestone {m.index + 1}</p>
          <p className="display tabular text-2xl font-bold">{usd(m.amount)}</p>
          <p className="text-sm text-[var(--muted)]">
            {bpsToPercent(m.bps)} of the job. {formatDuration(m.deliveryDuration)} to deliver, {formatDuration(m.reviewPeriod)} to review, {m.revisionsUsed} of {m.maxRevisions} changes used.
          </p>
        </div>
        <StatusBadge label={status.label} tone={status.tone} />
      </div>

      <ul className="mt-4 divide-y divide-[var(--border)] rounded-2xl bg-[var(--surface-muted)] px-4 text-sm">
        {m.payees.map((p, i) => {
          const share = m.shares[i] ?? 0
          const part = i === m.payees.length - 1
            ? m.amount - m.payees.slice(0, -1).reduce((acc, _, j) => acc + (m.amount * BigInt(m.shares[j] ?? 0)) / 10_000n, 0n)
            : (m.amount * BigInt(share)) / 10_000n
          return (
            <li key={p} className="flex items-center justify-between py-2.5">
              <span className="mono">{shortAddress(p)}</span>
              <span className="tabular text-[var(--ink-2)]">
                {bpsToPercent(share)} <span className="font-semibold">{usd(part)}</span>
              </span>
            </li>
          )
        })}
      </ul>

      {next && <p className="mt-4 text-sm text-[var(--ink-2)] text-pretty">{next}</p>}

      {!settled && signedIn && (
        <div className="mt-4 space-y-4">
          <ClientActions {...props} />
          <FreelancerActions {...props} />
          <ArbiterActions {...props} />
          {available.has('autoApprove') && (
            <ActionButton id={`auto-${m.index}`} pending={tx.pending} variant="ghost" onClick={() => void tx.call(`auto-${m.index}`, 'autoApprove', [bundle.job.id, BigInt(m.index)], 'Payment released.')}>
              Release payment (review time is over)
            </ActionButton>
          )}
          {available.has('timeout') && (
            <ActionButton id={`timeout-${m.index}`} pending={tx.pending} variant="ghost" onClick={() => void tx.call(`timeout-${m.index}`, 'resolveDisputeByTimeout', [bundle.job.id, BigInt(m.index)], 'Dispute closed with a 50/50 split.')}>
              Close dispute with a 50/50 split
            </ActionButton>
          )}
        </div>
      )}
    </article>
  )
}
