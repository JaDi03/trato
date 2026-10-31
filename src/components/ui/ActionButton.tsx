import clsx from 'clsx'
import { Loader2 } from 'lucide-react'
import type { ReactNode } from 'react'

interface ActionButtonProps {
  id: string
  /** The id of the action currently being sent, from useSend().pending */
  pending: string | null
  onClick: () => void
  children: ReactNode
  busyLabel?: string
  variant?: 'primary' | 'ghost' | 'danger'
  disabled?: boolean
  className?: string
}

export function ActionButton({
  id,
  pending,
  onClick,
  children,
  busyLabel = 'Confirming...',
  variant = 'primary',
  disabled,
  className,
}: ActionButtonProps) {
  const busy = pending === id
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled || pending !== null}
      className={clsx(
        'btn',
        variant === 'primary' && 'btn-primary',
        variant === 'ghost' && 'btn-ghost',
        variant === 'danger' && 'btn-danger',
        className,
      )}
    >
      {busy && <Loader2 className="h-4 w-4 animate-spin" aria-hidden />}
      {busy ? busyLabel : children}
    </button>
  )
}
