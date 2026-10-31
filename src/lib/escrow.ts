import type { Address } from 'viem'
import { sameAddress } from './format'

/** Mirrors the contract's fixed windows (seconds). */
export const START_WINDOW = 14 * 86_400
export const REJECTION_REFUND_DELAY = 7 * 86_400
export const DISPUTE_TIMEOUT = 30 * 86_400

export const MState = {
  Pending: 0,
  InProgress: 1,
  Delivered: 2,
  Approved: 3,
  InRevision: 4,
  Disputed: 5,
  Paid: 6,
  Refunded: 7,
} as const

export interface JobData {
  id: bigint
  client: Address
  freelancer: Address
  arbiter: Address
  total: bigint
  paid: bigint
  refunded: bigint
  remaining: bigint
  milestoneCount: number
  completed: boolean
  createdAt: number
}

export interface MilestoneData {
  index: number
  amount: bigint
  bps: number
  deliveryDuration: number
  reviewPeriod: number
  maxRevisions: number
  revisionsUsed: number
  state: number
  unlockedAt: number
  startedAt: number
  deadline: number
  deliveredAt: number
  rejectedFinal: boolean
  rejectedAt: number
  disputedAt: number
  payees: readonly Address[]
  shares: readonly number[]
  /** Client's open offer for a partial settlement (dollars back to the client), 0 when none. */
  proposedRefund: bigint
}

export interface JobBundle {
  job: JobData
  milestones: MilestoneData[]
}

export type Role = 'client' | 'freelancer' | 'arbiter' | 'payee'

export function rolesOf(address: Address | undefined, bundle: JobBundle): Role[] {
  if (!address) return []
  const roles: Role[] = []
  if (sameAddress(address, bundle.job.client)) roles.push('client')
  if (sameAddress(address, bundle.job.freelancer)) roles.push('freelancer')
  if (sameAddress(address, bundle.job.arbiter)) roles.push('arbiter')
  if (bundle.milestones.some((m) => m.payees.some((p) => sameAddress(p, address)))) roles.push('payee')
  return roles
}

export const ROLE_LABEL: Record<Role, string> = {
  client: 'Client',
  freelancer: 'Freelancer',
  arbiter: 'Arbiter',
  payee: 'Gets paid',
}

export type Tone = 'neutral' | 'active' | 'review' | 'good' | 'warn' | 'bad'

export function statusOf(m: MilestoneData): { label: string; tone: Tone } {
  switch (m.state) {
    case MState.Pending:
      return { label: m.unlockedAt > 0 ? 'Ready to start' : 'Waiting for earlier work', tone: 'neutral' }
    case MState.InProgress:
      return { label: 'Work in progress', tone: 'active' }
    case MState.Delivered:
      return m.rejectedFinal
        ? { label: 'Delivery rejected', tone: 'warn' }
        : { label: 'Ready for review', tone: 'review' }
    case MState.Approved:
      return { label: 'Approved', tone: 'good' }
    case MState.InRevision:
      return { label: 'Changes requested', tone: 'warn' }
    case MState.Disputed:
      return { label: 'In dispute', tone: 'bad' }
    case MState.Paid:
      return { label: 'Paid', tone: 'good' }
    case MState.Refunded:
      return { label: 'Returned to client', tone: 'neutral' }
    default:
      return { label: 'Unknown', tone: 'neutral' }
  }
}

export const isSettled = (m: MilestoneData) => m.state === MState.Paid || m.state === MState.Refunded

export type ActionKey =
  | 'start'
  | 'decline'
  | 'deliver'
  | 'freelancerDispute'
  | 'approve'
  | 'proposePartial'
  | 'cancelPartial'
  | 'acceptPartial'
  | 'declinePartial'
  | 'revise'
  | 'reject'
  | 'clientDispute'
  | 'refundLate'
  | 'refundRejected'
  | 'autoApprove'
  | 'timeout'
  | 'resolve'

/** Which actions a role can take on a milestone right now. Mirrors the contract's checks. */
export function availableActions(
  roles: Role[],
  bundle: JobBundle,
  m: MilestoneData,
  now: number,
): Set<ActionKey> {
  const out = new Set<ActionKey>()
  if (bundle.job.completed) return out
  const reviewEnd = m.deliveredAt + m.reviewPeriod
  const isDelivered = m.state === MState.Delivered

  if (roles.includes('freelancer')) {
    if (m.state === MState.Pending && m.unlockedAt > 0) out.add('start')
    const first = bundle.milestones[0]
    if (m.index === 0 && first?.state === MState.Pending) out.add('decline')
    if (m.state === MState.InProgress || m.state === MState.InRevision) out.add('deliver')
    if (isDelivered && m.rejectedFinal) out.add('freelancerDispute')
    if (isDelivered && m.proposedRefund > 0n) {
      out.add('acceptPartial')
      out.add('declinePartial')
    }
  }

  if (roles.includes('client')) {
    if (isDelivered) out.add('approve')
    if (isDelivered && m.amount > 1n) out.add('proposePartial')
    if (isDelivered && m.proposedRefund > 0n) out.add('cancelPartial')
    if (isDelivered && !m.rejectedFinal && now < reviewEnd) {
      if (m.revisionsUsed < m.maxRevisions) out.add('revise')
      else out.add('reject')
    }
    if (isDelivered && (m.rejectedFinal || now < reviewEnd)) out.add('clientDispute')
    const late =
      (m.state === MState.InProgress || m.state === MState.InRevision) && now > m.deadline
    const neverStarted = m.state === MState.Pending && m.unlockedAt > 0 && now > m.unlockedAt + START_WINDOW
    if (late || neverStarted) out.add('refundLate')
    if (isDelivered && m.rejectedFinal && now >= m.rejectedAt + REJECTION_REFUND_DELAY) out.add('refundRejected')
  }

  if (isDelivered && !m.rejectedFinal && now >= reviewEnd) out.add('autoApprove')
  if (m.state === MState.Disputed && now >= m.disputedAt + DISPUTE_TIMEOUT) out.add('timeout')
  if (m.state === MState.Disputed && roles.includes('arbiter')) out.add('resolve')
  return out
}
