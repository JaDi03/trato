import clsx from 'clsx'
import { ConnectKitButton } from 'connectkit'
import { Briefcase, Plus } from 'lucide-react'
import { useAccount } from 'wagmi'
import { useAvailableToWithdraw } from '@/hooks/useEscrow'
import type { Route } from '@/hooks/useRoute'
import { shortAddress, usd } from '@/lib/format'

interface HeaderProps {
  route: Route
  go: (route: Route) => void
}

export function Header({ route, go }: HeaderProps) {
  const { address } = useAccount()
  const { data: available } = useAvailableToWithdraw(address)

  const tab = (active: boolean) =>
    clsx(
      'inline-flex min-h-[44px] items-center gap-2 rounded-full px-4 text-sm font-semibold transition-colors',
      active ? 'bg-[var(--accent)] text-white' : 'text-[var(--ink-2)] hover:bg-white/70',
    )

  return (
    <header className="sticky top-0 z-30 border-b border-[var(--border)] bg-[rgba(249,249,252,0.85)] backdrop-blur-md">
      <div className="mx-auto flex max-w-3xl flex-wrap items-center justify-between gap-3 px-4 py-3">
        <button type="button" onClick={() => go({ name: 'jobs' })} className="display text-lg font-bold text-[var(--ink)]">
          Escrow
        </button>

        <nav className="flex items-center gap-1" aria-label="Main">
          <button type="button" className={tab(route.name === 'jobs' || route.name === 'job')} onClick={() => go({ name: 'jobs' })}>
            <Briefcase className="h-4 w-4" aria-hidden /> My jobs
          </button>
          <button type="button" className={tab(route.name === 'new')} onClick={() => go({ name: 'new' })}>
            <Plus className="h-4 w-4" aria-hidden /> New job
          </button>
        </nav>

        <div className="flex items-center gap-2">
          {available !== undefined && available > 0n && (
            <button
              type="button"
              onClick={() => go({ name: 'jobs' })}
              className="tabular min-h-[44px] rounded-full bg-[#e1f3e8] px-4 text-sm font-semibold text-[var(--success)]"
            >
              {usd(available)} ready to withdraw
            </button>
          )}
          <ConnectKitButton.Custom>
            {({ show, isConnected, address: connected }) => (
              <button type="button" onClick={show} className={clsx('btn', isConnected ? 'btn-ghost' : 'btn-primary')}>
                {isConnected && connected ? shortAddress(connected) : 'Sign in'}
              </button>
            )}
          </ConnectKitButton.Custom>
        </div>
      </div>
    </header>
  )
}
