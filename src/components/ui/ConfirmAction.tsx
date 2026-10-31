import { useEffect, useState, type ReactNode } from 'react'
import { ActionButton } from '@/components/ui/ActionButton'

interface ConfirmActionProps {
  id: string
  pending: string | null
  onConfirm: () => void
  children: ReactNode
  confirmLabel?: string
  variant?: 'primary' | 'ghost' | 'danger'
  disabled?: boolean
}

/** Two-tap button for actions that cannot be undone. */
export function ConfirmAction({
  id,
  pending,
  onConfirm,
  children,
  confirmLabel = 'Tap again to confirm',
  variant = 'danger',
  disabled,
}: ConfirmActionProps) {
  const [armed, setArmed] = useState(false)

  useEffect(() => {
    if (!armed) return
    const t = setTimeout(() => setArmed(false), 5_000)
    return () => clearTimeout(t)
  }, [armed])

  return (
    <ActionButton
      id={id}
      pending={pending}
      variant={variant}
      disabled={disabled}
      onClick={() => {
        if (!armed) {
          setArmed(true)
          return
        }
        setArmed(false)
        onConfirm()
      }}
    >
      {armed ? confirmLabel : children}
    </ActionButton>
  )
}
