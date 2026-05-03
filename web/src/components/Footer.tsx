import Link from "next/link";
import { APP_STORE_URL, SUPPORT_EMAIL } from "@/lib/constants";

// ---------------------------------------------------------------------------
// Types & data
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
      { label: "How it works", href: "#how-it-works" },
      { label: "Pricing", href: "#pricing" },
      { label: "Download", href: APP_STORE_URL, external: true },
    ],
  },
  {
    title: "Company",
    links: [
      { label: "Privacy", href: "/privacy" },
      { label: "Terms", href: "/terms" },
      { label: "Support", href: `mailto:${SUPPORT_EMAIL}`, external: true },
    ],
  },
];

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function FooterAnchor({ link }: { link: FooterLink }) {
  const className =
    "text-sm text-ink-400 transition-colors duration-200 hover:text-white";

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
// Footer
// ---------------------------------------------------------------------------

export default function Footer() {
  const year = new Date().getFullYear();

  return (
    <footer className="bg-ink-950 text-white">
      <div className="mx-auto max-w-7xl px-6 pb-8 pt-16 sm:px-8 lg:px-12">
        <div className="grid grid-cols-2 gap-x-8 gap-y-12 md:grid-cols-4">
          {/* Branding column */}
          <div className="col-span-2 min-w-0 md:col-span-2">
            <div className="flex items-center gap-2 text-xl tracking-tight select-none">
              <div className="flex h-9 w-9 items-center justify-center rounded-full bg-white shadow-sm">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src="/logo.png"
                  alt="ProEstimate"
                  className="h-5 w-5 object-contain"
                />
              </div>
              <span className="font-bold text-white">ProEstimate AI</span>
            </div>

            <p
              className="mt-4 text-sm leading-relaxed text-ink-400"
              style={{ maxWidth: "28rem" }}
            >
              AI-powered remodel previews, itemized material lists, and
              contractor-grade estimates &mdash; in under a minute. Built for
              the field, on iOS.
            </p>

            <p className="mt-6 text-xs text-ink-500">
              ProEstimate AI is a product of Viral Ventures LLC, Minnesota.
            </p>
          </div>

          {FOOTER_COLUMNS.map((column) => (
            <div key={column.title}>
              <h3 className="text-sm font-semibold uppercase tracking-wider text-ink-300">
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

      <div className="border-t border-ink-800">
        <div className="mx-auto flex max-w-7xl flex-col items-center justify-between gap-3 px-6 py-6 sm:flex-row sm:px-8 lg:px-12">
          <p className="text-xs text-ink-500">
            &copy; {year} Viral Ventures LLC. All rights reserved.
          </p>
          <ul className="flex items-center gap-6">
            <li>
              <Link
                href="/privacy"
                className="text-xs text-ink-400 transition-colors duration-200 hover:text-ink-300"
              >
                Privacy
              </Link>
            </li>
            <li>
              <Link
                href="/terms"
                className="text-xs text-ink-400 transition-colors duration-200 hover:text-ink-300"
              >
                Terms
              </Link>
            </li>
            <li>
              <Link
                href="/sitemap.xml"
                className="text-xs text-ink-400 transition-colors duration-200 hover:text-ink-300"
              >
                Sitemap
              </Link>
            </li>
          </ul>
        </div>
      </div>
    </footer>
  );
}
