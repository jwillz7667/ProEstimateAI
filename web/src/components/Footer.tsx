import Link from "next/link";

// ---------------------------------------------------------------------------
// Types & Data
// ---------------------------------------------------------------------------

interface FooterLink {
  label: string;
  href: string;
  external?: boolean;
}

interface FooterColumn {
  title: string;
  links: FooterLink[];
}

const FOOTER_COLUMNS: FooterColumn[] = [
  {
    title: "Product",
    links: [
      { label: "Features", href: "#features" },
      { label: "Pricing", href: "#pricing" },
      { label: "Download", href: "https://apps.apple.com/app/proestimate-ai/id0000000000", external: true },
      { label: "API", href: "/api" },
    ],
  },
  {
    title: "Legal",
    links: [
      { label: "Privacy Policy", href: "/privacy" },
      { label: "Terms of Service", href: "/terms" },
    ],
  },
  {
    title: "Connect",
    links: [
      { label: "Twitter", href: "https://twitter.com/proestimateai", external: true },
      { label: "Instagram", href: "https://instagram.com/proestimateai", external: true },
      { label: "LinkedIn", href: "https://linkedin.com/company/proestimateai", external: true },
      { label: "Support", href: "mailto:support@proestimate.ai", external: true },
    ],
  },
];

const BOTTOM_LINKS: FooterLink[] = [
  { label: "Privacy", href: "/privacy" },
  { label: "Terms", href: "/terms" },
  { label: "Sitemap", href: "/sitemap.xml" },
];

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

/** Renders a single link, choosing Next.js Link for internal and <a> for external */
function FooterAnchor({ link }: { link: FooterLink }) {
  const className =
    "text-sm text-gray-400 transition-colors duration-200 hover:text-white";

  if (link.external) {
    return (
      <a
        href={link.href}
        target="_blank"
        rel="noopener noreferrer"
        className={className}
      >
        {link.label}
      </a>
    );
  }

  return (
    <Link href={link.href} className={className}>
      {link.label}
    </Link>
  );
}

// ---------------------------------------------------------------------------
// Footer Component
// ---------------------------------------------------------------------------

export default function Footer() {
  return (
    <footer className="bg-gray-900 text-white">
      {/* Main footer grid */}
      <div className="mx-auto max-w-7xl px-6 pb-8 pt-16 sm:px-8 lg:px-12">
        <div className="grid grid-cols-2 gap-x-8 gap-y-12 md:grid-cols-4">
          {/* Column 1 — Company branding */}
          <div className="col-span-2 md:col-span-1">
            {/* Logo */}
            <div className="flex items-baseline gap-0.5 text-xl tracking-tight select-none">
              <span className="font-bold text-white">ProEstimate</span>
              <span className="font-bold text-brand-400">AI</span>
            </div>

            {/* Description */}
            <p className="mt-4 max-w-xs text-sm leading-relaxed text-gray-400">
              AI-powered remodel previews, material lists, and professional cost
              estimates for contractors and homeowners.
            </p>

            {/* Copyright (visible in company column on desktop) */}
            <p className="mt-6 text-xs text-gray-500">
              &copy; {new Date().getFullYear()} ProEstimate AI
            </p>
          </div>

          {/* Columns 2-4 — Links */}
          {FOOTER_COLUMNS.map((column) => (
            <div key={column.title}>
              <h3 className="text-sm font-semibold uppercase tracking-wider text-gray-300">
                {column.title}
              </h3>
              <ul className="mt-4 flex flex-col gap-3">
                {column.links.map((link) => (
                  <li key={link.label}>
                    <FooterAnchor link={link} />
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </div>

      {/* Bottom bar */}
      <div className="border-t border-gray-800">
        <div className="mx-auto flex max-w-7xl flex-col items-center justify-between gap-4 px-6 py-6 sm:flex-row sm:px-8 lg:px-12">
          <p className="text-xs text-gray-500">
            &copy; 2026 ProEstimate AI. All rights reserved.
          </p>

          <ul className="flex items-center gap-6">
            {BOTTOM_LINKS.map((link) => (
              <li key={link.label}>
                <Link
                  href={link.href}
                  className="text-xs text-gray-500 transition-colors duration-200 hover:text-gray-300"
                >
                  {link.label}
                </Link>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </footer>
  );
}
