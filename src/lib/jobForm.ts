import { isAddress, type Address } from 'viem'
import { daysToSeconds, parseDollars, sameAddress } from './format'

export interface PayeeDraft {
  key: string
  address: string
  percent: string
}

export interface MilestoneDraft {
  key: string
  percent: string
  deliveryDays: string
  reviewDays: string
  revisions: string
  payees: PayeeDraft[]
}

export interface JobDraft {
  total: string
  freelancer: string
  arbiter: string
  milestones: MilestoneDraft[]
}

export interface MilestoneInput {
  bps: number
  payees: Address[]
  shares: number[]
  deliveryDuration: number
  reviewPeriod: number
  maxRevisions: number
}

export const MAX_MILESTONES = 20
export const MAX_PAYEES = 10

let counter = 0
export const nextKey = () => `k${++counter}`

export const newPayee = (address = '', percent = '100'): PayeeDraft => ({ key: nextKey(), address, percent })

export const newMilestone = (percent = '100'): MilestoneDraft => ({
  key: nextKey(),
  percent,
  deliveryDays: '7',
  reviewDays: '3',
  revisions: '2',
  payees: [newPayee()],
})

export const emptyDraft = (): JobDraft => ({
  total: '',
  freelancer: '',
  arbiter: '',
  milestones: [newMilestone()],
})

/** "33.33" -> 3333. Returns null when not a number with at most two decimals. */
export function percentToBps(text: string): number | null {
  const clean = text.trim().replace('%', '')
  if (!/^\d+(\.\d{1,2})?$/.test(clean)) return null
  return Math.round(Number(clean) * 100)
}

export function sumBps(values: Array<number | null>): number {
  return values.reduce<number>((acc, v) => acc + (v ?? 0), 0)
}

export const milestoneBpsTotal = (draft: JobDraft) => sumBps(draft.milestones.map((m) => percentToBps(m.percent)))
export const payeeBpsTotal = (m: MilestoneDraft) => sumBps(m.payees.map((p) => percentToBps(p.percent)))

/** Dollar amount of each milestone, last one takes the rounding remainder (same as the contract). */
export function milestoneAmounts(total: bigint, draft: JobDraft): bigint[] {
  let allocated = 0n
  return draft.milestones.map((m, i) => {
    if (i === draft.milestones.length - 1) return total - allocated
    const amount = (total * BigInt(percentToBps(m.percent) ?? 0)) / 10_000n
    allocated += amount
    return amount
  })
}

export interface ValidationResult {
  errors: string[]
  total: bigint | null
  freelancer: Address | null
  arbiter: Address | null
  milestones: MilestoneInput[] | null
}

const wholeNumber = (text: string, min: number, max: number) => {
  if (!/^\d+$/.test(text.trim())) return null
  const n = Number(text)
  return n >= min && n <= max ? n : null
}

export function validateDraft(draft: JobDraft): ValidationResult {
  const errors: string[] = []
  const total = parseDollars(draft.total)
  if (total === null || total <= 0n) errors.push('Enter the total job amount in dollars.')

  const freelancerOk = isAddress(draft.freelancer)
  if (!freelancerOk) errors.push("Enter the freelancer's account ID (starts with 0x).")
  const arbiterOk = isAddress(draft.arbiter)
  if (!arbiterOk) errors.push("Enter the arbiter's account ID (starts with 0x).")
  if (freelancerOk && arbiterOk && sameAddress(draft.freelancer, draft.arbiter)) {
    errors.push('The arbiter must be someone other than the freelancer.')
  }

  if (draft.milestones.length === 0) errors.push('Add at least one milestone.')
  if (milestoneBpsTotal(draft) !== 10_000) errors.push('Milestone percentages must add up to exactly 100%.')

  const inputs: MilestoneInput[] = []
  draft.milestones.forEach((m, i) => {
    const label = `Milestone ${i + 1}`
    const bps = percentToBps(m.percent)
    if (bps === null || bps <= 0) errors.push(`${label}: enter a share of the job above 0%.`)
    const delivery = Number(m.deliveryDays)
    const review = Number(m.reviewDays)
    if (!(delivery > 0)) errors.push(`${label}: set the days allowed to deliver.`)
    if (!(review > 0)) errors.push(`${label}: set the days you get to review.`)
    const revisions = wholeNumber(m.revisions, 0, 20)
    if (revisions === null) errors.push(`${label}: enter how many changes you can ask for (0 to 20).`)

    if (payeeBpsTotal(m) !== 10_000) errors.push(`${label}: payee shares must add up to exactly 100%.`)
    const seen = new Set<string>()
    const addresses: Address[] = []
    const shares: number[] = []
    m.payees.forEach((p) => {
      const share = percentToBps(p.percent)
      if (!isAddress(p.address)) {
        errors.push(`${label}: every payee needs a valid account ID.`)
      } else {
        const lower = p.address.toLowerCase()
        if (seen.has(lower)) errors.push(`${label}: the same person is listed twice.`)
        seen.add(lower)
        if (sameAddress(p.address, draft.arbiter)) errors.push(`${label}: the arbiter cannot be paid on this job.`)
        addresses.push(p.address)
      }
      if (share === null || share <= 0) errors.push(`${label}: every payee needs a share above 0%.`)
      shares.push(share ?? 0)
    })

    inputs.push({
      bps: bps ?? 0,
      payees: addresses,
      shares,
      deliveryDuration: daysToSeconds(delivery),
      reviewPeriod: daysToSeconds(review),
      maxRevisions: revisions ?? 0,
    })
  })

  const unique = Array.from(new Set(errors))
  return {
    errors: unique,
    total,
    freelancer: freelancerOk ? (draft.freelancer as Address) : null,
    arbiter: arbiterOk ? (draft.arbiter as Address) : null,
    milestones: unique.length === 0 ? inputs : null,
  }
}
