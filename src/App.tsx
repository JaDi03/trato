import { Header } from '@/components/Header'
import { Notices } from '@/components/Notices'
import { JobList } from '@/components/JobList'
import { JobDetail } from '@/components/JobDetail'
import { CreateJobForm } from '@/components/CreateJobForm'
import { useRoute } from '@/hooks/useRoute'

export default function App() {
  const { route, go } = useRoute()

  return (
    <div className="min-h-dvh">
      <Header route={route} go={go} />
      <Notices />
      <main className="mx-auto max-w-3xl px-4 pb-28 pt-6">
        {route.name === 'jobs' && <JobList go={go} />}
        {route.name === 'new' && <CreateJobForm go={go} />}
        {route.name === 'job' && <JobDetail jobId={route.id} go={go} />}
      </main>
    </div>
  )
}
