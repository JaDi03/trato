import { AlertTriangle } from 'lucide-react'
import { useAccount, useSwitchChain } from 'wagmi'
import { appChain } from '@/config'
import { CHAIN_ID, ENV_PROBLEMS } from '@/lib/env'

export function Notices() {
  const { isConnected, chainId } = useAccount()
  const { switchChain, isPending } = useSwitchChain()
  const wrongNetwork = isConnected && chainId !== CHAIN_ID

  if (ENV_PROBLEMS.length === 0 && !wrongNetwork) return null

  return (
    <div className="mx-auto mt-4 max-w-3xl space-y-3 px-4">
      {ENV_PROBLEMS.length > 0 && (
        <div role="alert" className="card flex gap-3 border-[rgba(186,43,76,0.35)] p-4">
          <AlertTriangle className="mt-0.5 h-5 w-5 shrink-0 text-[var(--danger)]" aria-hidden />
          <div className="text-sm">
            <p className="font-semibold text-[var(--danger)]">The app is not fully set up</p>
            <ul className="mt-1 list-disc pl-5 text-[var(--ink-2)]">
              {ENV_PROBLEMS.map((problem) => (
                <li key={problem}>{problem}</li>
              ))}
            </ul>
          </div>
        </div>
      )}
      {wrongNetwork && (
        <div className="card flex flex-wrap items-center justify-between gap-3 p-4">
          <p className="text-sm text-[var(--ink-2)]">This app runs on {appChain.name}. Switch to continue.</p>
          <button type="button" className="btn btn-primary" disabled={isPending} onClick={() => switchChain({ chainId: CHAIN_ID })}>
            {isPending ? 'Switching...' : `Switch to ${appChain.name}`}
          </button>
        </div>
      )}
    </div>
  )
}
