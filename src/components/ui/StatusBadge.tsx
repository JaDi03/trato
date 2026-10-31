import clsx from 'clsx'
import type { Tone } from '@/lib/escrow'

const TONES: Record<Tone, string> = {
  neutral: 'bg-[#eef0f5] text-[#334155]',
  active: 'bg-[#e4eefb] text-[#0f4c86]',
  review: 'bg-[#fdf1d8] text-[#8a5a00]',
  good: 'bg-[#e1f3e8] text-[#1a8047]',
  warn: 'bg-[#fdebd9] text-[#a2530a]',
  bad: 'bg-[#fbe3e8] text-[#ba2b4c]',
}

export function StatusBadge({ label, tone }: { label: string; tone: Tone }) {
  return (
    <span className={clsx('inline-flex items-center rounded-full px-3 py-1 text-xs font-semibold', TONES[tone])}>
      {label}
    </span>
  )
}
