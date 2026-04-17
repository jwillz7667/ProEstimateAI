import Link from "next/link";

export default function NotFound() {
  return (
    <main className="min-h-screen bg-surface-secondary flex items-center justify-center px-6">
      <div className="max-w-md text-center">
        <div className="inline-flex h-16 w-16 items-center justify-center rounded-full bg-brand-100 text-brand-600 mb-6 text-3xl">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth={2}
            strokeLinecap="round"
            strokeLinejoin="round"
            className="h-8 w-8"
          >
            <circle cx="12" cy="12" r="10" />
            <line x1="12" y1="8" x2="12" y2="12" />
            <line x1="12" y1="16" x2="12.01" y2="16" />
          </svg>
        </div>

        <h1 className="text-3xl font-bold text-ink-950 mb-3">
          Proposal not found
        </h1>
        <p className="text-ink-600 leading-relaxed mb-8">
          This proposal link is invalid, has been revoked, or the contractor may
          have deleted it. Please reach out to whoever shared this with you for
          an updated link.
        </p>

        <Link
          href="/"
          className="inline-flex items-center gap-2 rounded-full bg-brand-500 px-6 py-3 font-medium text-white transition hover:bg-brand-600"
        >
          <span>Back to ProEstimate AI</span>
        </Link>
      </div>
    </main>
  );
}
