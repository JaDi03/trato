import { useCallback, useEffect, useState } from 'react'

export type Route = { name: 'jobs' } | { name: 'new' } | { name: 'job'; id: bigint }

function parse(): Route {
  const params = new URLSearchParams(window.location.search)
  const job = params.get('job')
  if (job && /^\d+$/.test(job)) return { name: 'job', id: BigInt(job) }
  if (params.get('view') === 'new') return { name: 'new' }
  return { name: 'jobs' }
}

function toUrl(route: Route): string {
  if (route.name === 'job') return `/?job=${route.id.toString()}`
  if (route.name === 'new') return '/?view=new'
  return '/'
}

/** Tiny query-string router so every job screen has a link that works on first load. */
export function useRoute() {
  const [route, setRoute] = useState<Route>(parse)

  useEffect(() => {
    const onPop = () => setRoute(parse())
    window.addEventListener('popstate', onPop)
    return () => window.removeEventListener('popstate', onPop)
  }, [])

  const go = useCallback((next: Route) => {
    window.history.pushState({}, '', toUrl(next))
    setRoute(next)
    window.scrollTo({ top: 0 })
  }, [])

  return { route, go }
}
