import type { useSend } from '@/hooks/useTx'
import type { ActionKey, JobBundle, MilestoneData } from '@/lib/escrow'

export interface ActionProps {
  bundle: JobBundle
  milestone: MilestoneData
  available: Set<ActionKey>
  tx: ReturnType<typeof useSend>
  now: number
}
