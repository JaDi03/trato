import { formatUsdc, parseUsdc } from '@/onchain-money'

/** Raw USDC amount to "$1,234.50". Shows extra decimals only when needed. */
export function usd(raw: bigint): string {
  const text = formatUsdc(raw)
  const negative = text.startsWith('-')
  const [whole, frac = ''] = text.replace('-', '').split('.')
  const trimmed = frac.replace(/0+$/, '')
  const cents = trimmed.length <= 2 ? trimmed.padEnd(2, '0') : trimmed
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',')
  return `${negative ? '-' : ''}$${grouped}.${cents}`
}

/** Parses user text such as "1,200.50" or "$40" into raw USDC, or null if invalid. */
export function parseDollars(text: string): bigint | null {
  const clean = text.replace(/[$,\s]/g, '')
  if (!clean || !/^\d*\.?\d*$/.test(clean) || clean === '.') return null
  try {
    return parseUsdc(clean)
  } catch {
    return null
  }
}

export function bpsToPercent(bps: number): string {
  const value = bps / 100
  return `${Number.isInteger(value) ? value : value.toFixed(2).replace(/0+$/, '')}%`
}

const DAY = 86_400
const HOUR = 3_600
const MINUTE = 60

export function daysToSeconds(days: number): number {
  return Math.round(days * DAY)
}

/** 604800 -> "7 days". */
export function formatDuration(seconds: number): string {
  if (seconds >= DAY) {
    const d = seconds / DAY
    const text = Number.isInteger(d) ? String(d) : d.toFixed(1)
    return `${text} ${d === 1 ? 'day' : 'days'}`
  }
  if (seconds >= HOUR) {
    const h = Math.round(seconds / HOUR)
    return `${h} ${h === 1 ? 'hour' : 'hours'}`
  }
  const m = Math.max(1, Math.round(seconds / MINUTE))
  return `${m} ${m === 1 ? 'minute' : 'minutes'}`
}

/** Seconds remaining until `target` (unix seconds) as "3 days 4 hours" or "now". */
export function timeUntil(target: number, now: number): string {
  const left = target - now
  if (left <= 0) return 'now'
  if (left >= DAY) {
    const d = Math.floor(left / DAY)
    const h = Math.floor((left % DAY) / HOUR)
    return h > 0 ? `${d}d ${h}h` : `${d}d`
  }
  if (left >= HOUR) {
    const h = Math.floor(left / HOUR)
    const m = Math.floor((left % HOUR) / MINUTE)
    return m > 0 ? `${h}h ${m}m` : `${h}h`
  }
  if (left >= MINUTE) return `${Math.floor(left / MINUTE)}m`
  return `${left}s`
}

export function shortAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`
}

export function sameAddress(a?: string, b?: string): boolean {
  return !!a && !!b && a.toLowerCase() === b.toLowerCase()
}

export function nowSeconds(): number {
  return Math.floor(Date.now() / 1000)
}
