import { Wallet } from 'lucide-react'
import { useAccount } from 'wagmi'
import { ActionButton } from '@/components/ui/ActionButton'
import { useAvailableToWithdraw } from '@/hooks/useEscrow'
import { useSend } from '@/hooks/useTx'
import { usd } from '@/lib/format'

export function PayoutsPanel() {
  const { address } = useAccount()
  const { data: available } = useAvailableToWithdraw(address)
  const { call, pending } = useSend()

  if (!address || available === undefined) return null
  const hasMoney = available > 0n

  return (
    <section className="card flex flex-wrap items-center justify-between gap-4 p-5" aria-label="Your payouts">
      <div className="flex items-center gap-3">
        <span className="flex h-11 w-11 items-center justify-center rounded-2xl bg-[var(--surface-muted)]">
          <Wallet className="h-5 w-5 text-[var(--accent-hover)]" aria-hidden />
        </span>
        <div>
          <p className="label mb-0">Ready to withdraw</p>
          <p className="display tabular text-3xl font-bold">{usd(available)}</p>
        </div>
      </div>
      <ActionButton id="withdraw" pending={pending} disabled={!hasMoney} onClick={() => void call('withdraw', 'withdraw', [], 'Your money was sent to your account.')} busyLabel="Withdrawing...">
        Withdraw {hasMoney ? usd(available) : ''}
      </ActionButton>
    </section>
  )
}
