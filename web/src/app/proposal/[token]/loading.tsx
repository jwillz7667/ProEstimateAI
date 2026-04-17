export default function Loading() {
  return (
    <main className="min-h-screen bg-surface-secondary">
      <div className="mx-auto max-w-3xl px-6 py-12 animate-pulse">
        <div className="h-8 w-40 bg-ink-100 rounded-md mb-8" />
        <div className="h-64 w-full bg-ink-100 rounded-2xl mb-8" />
        <div className="h-10 w-3/4 bg-ink-100 rounded-md mb-4" />
        <div className="h-4 w-full bg-ink-100 rounded-md mb-2" />
        <div className="h-4 w-5/6 bg-ink-100 rounded-md mb-12" />
        <div className="space-y-3">
          {Array.from({ length: 6 }).map((_, i) => (
            <div key={i} className="h-12 w-full bg-ink-100 rounded-md" />
          ))}
        </div>
      </div>
    </main>
  );
}
