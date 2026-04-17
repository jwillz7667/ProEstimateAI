import type { Metadata } from "next";
import { notFound } from "next/navigation";
import Link from "next/link";

import {
  formatCurrency,
  formatDate,
  formatQuantity,
  getSharedProposal,
  groupLineItems,
  isProposalExpired,
  isProposalOpen,
  type SharedLineItem,
  type SharedProposalPage,
} from "@/lib/proposal";
import { APIError } from "@/lib/api";

import { ProposalActions } from "./ProposalActions";

interface Params {
  params: Promise<{ token: string }>;
}

// ─── Metadata (for iMessage / social preview) ────────────────────────────────

export async function generateMetadata({ params }: Params): Promise<Metadata> {
  const { token } = await params;
  try {
    const data = await getSharedProposal(token);
    const title = data.proposal.title
      ? `${data.proposal.title} — ${data.company.name}`
      : `${data.project.title} — Proposal from ${data.company.name}`;
    const description = data.proposal.client_message
      ? data.proposal.client_message
      : `Review the proposal for ${data.project.title}.`;
    return {
      title,
      description,
      robots: { index: false, follow: false },
      openGraph: {
        title,
        description,
        type: "website",
        images: data.proposal.hero_image_url
          ? [{ url: data.proposal.hero_image_url }]
          : undefined,
      },
    };
  } catch {
    return {
      title: "Proposal",
      robots: { index: false, follow: false },
    };
  }
}

// ─── Page ────────────────────────────────────────────────────────────────────

export default async function ProposalPage({ params }: Params) {
  const { token } = await params;

  let data: SharedProposalPage;
  try {
    data = await getSharedProposal(token);
  } catch (err) {
    if (err instanceof APIError && err.status === 404) {
      notFound();
    }
    throw err;
  }

  const { company, project, estimate, proposal, before_after_images } = data;
  const accent = company.primary_color || "#FF9230";
  const groups = groupLineItems(estimate.line_items);
  const expired = isProposalExpired(proposal);
  const open = isProposalOpen(proposal) && !expired;

  return (
    <main
      className="min-h-screen bg-surface-secondary"
      style={{ "--accent": accent } as React.CSSProperties}
    >
      {/* Accent bar */}
      <div className="h-1.5 w-full" style={{ backgroundColor: accent }} />

      <div className="mx-auto max-w-3xl px-6 py-10 lg:py-16">
        {/* Header ---------------------------------------------------------- */}
        <header className="mb-10 flex items-center justify-between gap-6">
          <div className="flex items-center gap-4">
            {company.logo_url ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={company.logo_url}
                alt={`${company.name} logo`}
                className="h-12 w-12 rounded-xl object-contain bg-white p-1 ring-1 ring-ink-100"
              />
            ) : (
              <div
                className="flex h-12 w-12 items-center justify-center rounded-xl font-bold text-white"
                style={{ backgroundColor: accent }}
                aria-hidden
              >
                {company.name.slice(0, 1).toUpperCase()}
              </div>
            )}
            <div>
              <div className="text-sm uppercase tracking-widest text-ink-500">
                Proposal from
              </div>
              <div className="text-lg font-semibold text-ink-950">
                {company.name}
              </div>
            </div>
          </div>
          <StatusPill proposal={proposal} expired={expired} />
        </header>

        {/* Status banner --------------------------------------------------- */}
        {!open && (
          <StatusBanner proposal={proposal} expired={expired} accent={accent} />
        )}

        {/* Hero ------------------------------------------------------------ */}
        {proposal.hero_image_url && (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={proposal.hero_image_url}
            alt={project.title}
            className="mb-8 w-full rounded-2xl border border-ink-100 object-cover aspect-[3/2]"
          />
        )}

        {/* Title + intro --------------------------------------------------- */}
        <section className="mb-10">
          {proposal.proposal_number && (
            <div className="text-sm font-medium uppercase tracking-wide text-ink-500">
              {proposal.proposal_number}
            </div>
          )}
          <h1 className="mt-1 text-3xl sm:text-4xl font-bold leading-tight text-ink-950">
            {proposal.title || project.title}
          </h1>
          {project.description && (
            <p className="mt-4 text-lg leading-relaxed text-ink-700">
              {project.description}
            </p>
          )}
          {proposal.client_message && (
            <blockquote
              className="mt-6 rounded-xl border-l-4 px-5 py-4 text-ink-700 italic"
              style={{
                backgroundColor: `${accent}12`,
                borderLeftColor: accent,
              }}
            >
              {proposal.client_message}
            </blockquote>
          )}
          {proposal.intro_text && (
            <RichBlock>{proposal.intro_text}</RichBlock>
          )}
        </section>

        {/* Before/after gallery ------------------------------------------- */}
        {before_after_images.length > 0 && (
          <section className="mb-10">
            <SectionHeading>Project Photos</SectionHeading>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
              {before_after_images.map((img) => (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  key={img.asset_id}
                  src={img.url}
                  alt={`${img.asset_type} photo`}
                  className="aspect-square w-full rounded-lg border border-ink-100 object-cover"
                />
              ))}
            </div>
          </section>
        )}

        {/* Scope of work --------------------------------------------------- */}
        {proposal.scope_of_work && (
          <section className="mb-10">
            <SectionHeading>Scope of Work</SectionHeading>
            <RichBlock>{proposal.scope_of_work}</RichBlock>
          </section>
        )}

        {/* Timeline -------------------------------------------------------- */}
        {proposal.timeline_text && (
          <section className="mb-10">
            <SectionHeading>Timeline</SectionHeading>
            <RichBlock>{proposal.timeline_text}</RichBlock>
          </section>
        )}

        {/* Line items ------------------------------------------------------ */}
        <section className="mb-10">
          <SectionHeading>Pricing</SectionHeading>

          <div className="overflow-hidden rounded-2xl border border-ink-100 bg-white">
            {groups.materials.length > 0 && (
              <LineItemGroup
                label="Materials"
                items={groups.materials}
                subtotal={estimate.subtotal_materials}
              />
            )}
            {groups.labor.length > 0 && (
              <LineItemGroup
                label="Labor"
                items={groups.labor}
                subtotal={estimate.subtotal_labor}
                divided={groups.materials.length > 0}
              />
            )}
            {groups.other.length > 0 && (
              <LineItemGroup
                label="Other"
                items={groups.other}
                subtotal={estimate.subtotal_other}
                divided={
                  groups.materials.length > 0 || groups.labor.length > 0
                }
              />
            )}

            {/* Totals */}
            <div className="border-t border-ink-100 bg-ink-50 px-4 sm:px-6 py-5 space-y-2">
              <TotalRow
                label="Subtotal"
                value={formatCurrency(
                  estimate.subtotal_materials +
                    estimate.subtotal_labor +
                    estimate.subtotal_other,
                )}
              />
              {estimate.discount_amount > 0 && (
                <TotalRow
                  label="Discount"
                  value={`− ${formatCurrency(estimate.discount_amount)}`}
                />
              )}
              {estimate.tax_amount > 0 && (
                <TotalRow
                  label="Tax"
                  value={formatCurrency(estimate.tax_amount)}
                />
              )}
              <div className="flex items-baseline justify-between pt-3 border-t border-ink-200">
                <span className="text-base font-semibold text-ink-950">
                  Total
                </span>
                <span
                  className="text-2xl font-bold tabular-nums"
                  style={{ color: accent }}
                >
                  {formatCurrency(estimate.total_amount)}
                </span>
              </div>
            </div>
          </div>
        </section>

        {/* Actions --------------------------------------------------------- */}
        {open && (
          <section className="mb-10">
            <ProposalActions token={token} primaryColor={accent} />
            {proposal.expires_at && (
              <p className="mt-3 text-sm text-ink-500 text-center">
                This proposal expires {formatDate(proposal.expires_at)}.
              </p>
            )}
          </section>
        )}

        {/* Terms ----------------------------------------------------------- */}
        {proposal.terms_and_conditions && (
          <section className="mb-10">
            <SectionHeading>Terms &amp; Conditions</SectionHeading>
            <RichBlock muted>{proposal.terms_and_conditions}</RichBlock>
          </section>
        )}

        {/* Footer ---------------------------------------------------------- */}
        <footer className="mt-16 border-t border-ink-100 pt-8 text-sm text-ink-500">
          {proposal.footer_text && (
            <p className="mb-6 whitespace-pre-line">{proposal.footer_text}</p>
          )}
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
            <div>
              <div className="font-semibold text-ink-700">{company.name}</div>
              {(company.address || company.city) && (
                <div>
                  {[company.address, company.city, company.state, company.zip]
                    .filter(Boolean)
                    .join(", ")}
                </div>
              )}
              <div className="flex flex-wrap gap-x-4 gap-y-1 mt-1">
                {company.phone && <span>{company.phone}</span>}
                {company.email && (
                  <a
                    href={`mailto:${company.email}`}
                    className="hover:text-brand-600"
                  >
                    {company.email}
                  </a>
                )}
                {company.website_url && (
                  <a
                    href={company.website_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="hover:text-brand-600"
                  >
                    {company.website_url.replace(/^https?:\/\//, "")}
                  </a>
                )}
              </div>
            </div>
            <Link
              href="/"
              className="inline-flex items-center gap-1 text-ink-500 hover:text-brand-600"
            >
              Powered by ProEstimate AI →
            </Link>
          </div>
        </footer>
      </div>
    </main>
  );
}

// ─── Subcomponents ──────────────────────────────────────────────────────────

function SectionHeading({ children }: { children: React.ReactNode }) {
  return (
    <h2 className="text-xl font-semibold text-ink-950 mb-4">{children}</h2>
  );
}

function RichBlock({
  children,
  muted,
}: {
  children: string;
  muted?: boolean;
}) {
  return (
    <div
      className={`whitespace-pre-line leading-relaxed ${
        muted ? "text-ink-600 text-sm" : "text-ink-700"
      }`}
    >
      {children}
    </div>
  );
}

function TotalRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-baseline justify-between text-sm">
      <span className="text-ink-600">{label}</span>
      <span className="text-ink-900 tabular-nums">{value}</span>
    </div>
  );
}

function LineItemGroup({
  label,
  items,
  subtotal,
  divided,
}: {
  label: string;
  items: SharedLineItem[];
  subtotal: number;
  divided?: boolean;
}) {
  return (
    <div className={divided ? "border-t border-ink-100" : ""}>
      <div className="px-4 sm:px-6 pt-5 pb-2 text-xs font-semibold uppercase tracking-wider text-ink-500">
        {label}
      </div>
      <ul className="divide-y divide-ink-100">
        {items.map((item, idx) => (
          <li
            key={`${label}-${idx}`}
            className="flex items-start gap-4 px-4 sm:px-6 py-3"
          >
            <div className="flex-1 min-w-0">
              <div className="font-medium text-ink-900">{item.name}</div>
              {item.description && (
                <div className="text-sm text-ink-500 mt-0.5">
                  {item.description}
                </div>
              )}
              <div className="mt-1 text-xs text-ink-500 tabular-nums">
                {formatQuantity(item.quantity)} {item.unit} ·{" "}
                {formatCurrency(item.unit_cost)} each
              </div>
            </div>
            <div className="text-right text-ink-900 font-medium tabular-nums shrink-0">
              {formatCurrency(item.line_total)}
            </div>
          </li>
        ))}
      </ul>
      <div className="flex justify-between px-4 sm:px-6 py-3 bg-surface-tertiary/60 text-sm">
        <span className="text-ink-600">Subtotal</span>
        <span className="font-semibold text-ink-900 tabular-nums">
          {formatCurrency(subtotal)}
        </span>
      </div>
    </div>
  );
}

function StatusPill({
  proposal,
  expired,
}: {
  proposal: SharedProposalPage["proposal"];
  expired: boolean;
}) {
  const status = expired ? "expired" : proposal.status;
  const { label, bg, fg } = (() => {
    switch (status) {
      case "approved":
        return { label: "Approved", bg: "#DCFCE7", fg: "#166534" };
      case "declined":
        return { label: "Declined", bg: "#FEE2E2", fg: "#991B1B" };
      case "expired":
        return { label: "Expired", bg: "#F3F4F6", fg: "#4B5563" };
      case "viewed":
        return { label: "Viewed", bg: "#FEF3C7", fg: "#92400E" };
      case "sent":
        return { label: "Awaiting review", bg: "#FEF3C7", fg: "#92400E" };
      default:
        return { label: status, bg: "#F3F4F6", fg: "#4B5563" };
    }
  })();
  return (
    <span
      className="inline-flex items-center rounded-full px-3 py-1 text-xs font-semibold"
      style={{ backgroundColor: bg, color: fg }}
    >
      {label}
    </span>
  );
}

function StatusBanner({
  proposal,
  expired,
  accent,
}: {
  proposal: SharedProposalPage["proposal"];
  expired: boolean;
  accent: string;
}) {
  if (proposal.status === "approved") {
    const date = formatDate(proposal.responded_at);
    return (
      <Banner
        tone="success"
        title="Thanks — this proposal was approved"
        body={
          date
            ? `You approved this proposal on ${date}. The contractor has been notified.`
            : "The contractor has been notified."
        }
      />
    );
  }
  if (proposal.status === "declined") {
    const date = formatDate(proposal.responded_at);
    return (
      <Banner
        tone="neutral"
        title="This proposal was declined"
        body={
          date
            ? `You declined this proposal on ${date}. The contractor has been notified.`
            : "The contractor has been notified."
        }
      />
    );
  }
  if (expired) {
    return (
      <Banner
        tone="neutral"
        title="This proposal has expired"
        body="Please ask the contractor to send an updated version."
      />
    );
  }
  if (proposal.status === "draft") {
    return (
      <Banner
        tone="neutral"
        title="This proposal isn't ready yet"
        body="The contractor hasn't finished preparing this proposal. Check back shortly."
        accent={accent}
      />
    );
  }
  return null;
}

function Banner({
  tone,
  title,
  body,
}: {
  tone: "success" | "neutral";
  title: string;
  body: string;
  accent?: string;
}) {
  const { bg, border, fg } =
    tone === "success"
      ? { bg: "#DCFCE7", border: "#86EFAC", fg: "#166534" }
      : { bg: "#F3F4F6", border: "#D4D7DD", fg: "#1F2937" };
  return (
    <div
      className="mb-8 rounded-2xl border px-5 py-4"
      style={{ backgroundColor: bg, borderColor: border }}
    >
      <div className="font-semibold" style={{ color: fg }}>
        {title}
      </div>
      <div className="mt-1 text-sm" style={{ color: fg }}>
        {body}
      </div>
    </div>
  );
}
