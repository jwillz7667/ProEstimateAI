"use client";

import { motion, type Variants } from "framer-motion";

// ---------------------------------------------------------------------------
// Real-estimate proof section — uses the actual EAT-1043 estimate rendered
// from the iOS app. Pages live under /public/sample.
// ---------------------------------------------------------------------------

const PAGES = [
  { src: "/sample/estimate-page-1.jpg", alt: "Estimate cover with before/after photos and material line items" },
  { src: "/sample/estimate-page-2.jpg", alt: "Labor breakdown, totals, and scope assumptions" },
  { src: "/sample/estimate-page-3.jpg", alt: "Exclusions, notes, and warranty terms" },
] as const;

const HIGHLIGHTS = [
  "AI-generated before / after on the cover",
  "Itemized materials with descriptions and unit cost",
  "Labor hours and equipment rentals separated",
  "Auto-calculated tax based on your company profile",
  "Scope, exclusions, and warranty in plain language",
] as const;

// ---------------------------------------------------------------------------
// Animation variants
// ---------------------------------------------------------------------------

const headerVariants: Variants = {
  hidden: { opacity: 0, y: 24 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.6, ease: [0.16, 1, 0.3, 1] as const },
  },
};

const stackVariants: Variants = {
  hidden: { opacity: 0, y: 40 },
  visible: {
    opacity: 1,
    y: 0,
    transition: {
      duration: 0.7,
      ease: [0.16, 1, 0.3, 1] as const,
      staggerChildren: 0.15,
      delayChildren: 0.1,
    },
  },
};

const pageVariants: Variants = {
  hidden: { opacity: 0, y: 30, rotate: 0 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.7, ease: [0.16, 1, 0.3, 1] as const },
  },
};

const copyVariants: Variants = {
  hidden: { opacity: 0, y: 30 },
  visible: {
    opacity: 1,
    y: 0,
    transition: {
      duration: 0.7,
      ease: [0.16, 1, 0.3, 1] as const,
      staggerChildren: 0.08,
      delayChildren: 0.25,
    },
  },
};

const itemVariants: Variants = {
  hidden: { opacity: 0, y: 14 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.5, ease: [0.16, 1, 0.3, 1] as const },
  },
};

// ---------------------------------------------------------------------------
// Inline icons
// ---------------------------------------------------------------------------

function CheckIcon({ className }: { className?: string }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 20 20"
      fill="currentColor"
      aria-hidden="true"
      className={className ?? "h-4 w-4"}
    >
      <path
        fillRule="evenodd"
        d="M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 0 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z"
        clipRule="evenodd"
      />
    </svg>
  );
}

function DownloadIcon({ className }: { className?: string }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      width="18"
      height="18"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      className={className}
    >
      <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
      <polyline points="7 10 12 15 17 10" />
      <line x1="12" y1="15" x2="12" y2="3" />
    </svg>
  );
}

// ---------------------------------------------------------------------------
// PDF page card — one stacked sheet
// ---------------------------------------------------------------------------

interface PageCardProps {
  src: string;
  alt: string;
  rotate: number;
  z: number;
  offsetX: number;
  offsetY: number;
}

function PageCard({ src, alt, rotate, z, offsetX, offsetY }: PageCardProps) {
  return (
    <motion.div
      variants={pageVariants}
      whileHover={{ y: offsetY - 8, rotate: rotate * 0.6, transition: { duration: 0.3 } }}
      className="absolute left-1/2 top-0 -translate-x-1/2 origin-center"
      style={{
        zIndex: z,
        transform: `translateX(calc(-50% + ${offsetX}px)) translateY(${offsetY}px) rotate(${rotate}deg)`,
      }}
    >
      <div className="relative w-[280px] sm:w-[320px] lg:w-[360px] overflow-hidden rounded-xl bg-white shadow-2xl ring-1 ring-ink-200/60">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={src}
          alt={alt}
          loading="lazy"
          className="block h-auto w-full"
        />
      </div>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// Section
// ---------------------------------------------------------------------------

export default function EstimateShowcase() {
  return (
    <section
      id="estimate-sample"
      className="relative overflow-hidden bg-ink-50 py-24 sm:py-32 lg:py-36"
    >
      {/* Decorative blobs */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -left-32 top-1/3 h-[420px] w-[420px] rounded-full bg-brand-100/60 blur-3xl"
      />
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -right-24 -bottom-24 h-[420px] w-[420px] rounded-full bg-brand-50/80 blur-3xl"
      />

      <div className="relative mx-auto max-w-7xl px-6 sm:px-8 lg:px-12">
        {/* Section header */}
        <motion.div
          variants={headerVariants}
          initial="hidden"
          whileInView="visible"
          viewport={{ once: true, margin: "-80px" }}
          className="mx-auto max-w-2xl text-center"
        >
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-brand-600">
            The deliverable
          </p>
          <h2 className="mt-3 text-4xl font-bold tracking-tight text-balance text-ink-950 sm:text-5xl">
            Real estimates. Branded PDFs. Sent in seconds.
          </h2>
          <p className="mt-5 text-lg leading-relaxed text-pretty text-ink-500">
            This is an actual landscape install estimate generated by the app
            &mdash; before / after photos on the cover, every line itemized, tax
            and totals computed automatically.
          </p>
        </motion.div>

        {/* Body */}
        <div className="mt-20 grid grid-cols-1 items-center gap-16 lg:grid-cols-[1.05fr_1fr] lg:gap-20">
          {/* ---- Left: stacked PDF pages ---- */}
          <motion.div
            variants={stackVariants}
            initial="hidden"
            whileInView="visible"
            viewport={{ once: true, margin: "-100px" }}
            className="relative mx-auto h-[560px] w-full max-w-[480px] sm:h-[620px] lg:h-[680px]"
          >
            {/* Soft glow */}
            <div
              aria-hidden="true"
              className="pointer-events-none absolute inset-x-0 top-1/4 -z-10 h-2/3 rounded-[3rem] bg-brand-200/40 blur-3xl"
            />

            {/* Back two pages, fanning out */}
            <PageCard
              src={PAGES[2].src}
              alt={PAGES[2].alt}
              rotate={6}
              z={1}
              offsetX={68}
              offsetY={52}
            />
            <PageCard
              src={PAGES[1].src}
              alt={PAGES[1].alt}
              rotate={-4}
              z={2}
              offsetX={-58}
              offsetY={28}
            />
            {/* Front page — the hero sheet */}
            <PageCard
              src={PAGES[0].src}
              alt={PAGES[0].alt}
              rotate={1}
              z={3}
              offsetX={0}
              offsetY={0}
            />
          </motion.div>

          {/* ---- Right: highlights + CTA ---- */}
          <motion.div
            variants={copyVariants}
            initial="hidden"
            whileInView="visible"
            viewport={{ once: true, margin: "-100px" }}
            className="min-w-0"
          >
            <motion.h3
              variants={itemVariants}
              className="text-2xl font-bold tracking-tight text-balance text-ink-950 sm:text-3xl"
            >
              EAT-1043 &middot; Landscape Install
            </motion.h3>

            <motion.p
              variants={itemVariants}
              className="mt-3 text-base leading-relaxed text-pretty text-ink-500 sm:text-lg"
            >
              The contractor uploaded one photo of an overgrown front yard,
              picked a style direction, and walked away with this proposal in
              under a minute. No spreadsheets. No back-office.
            </motion.p>

            <motion.ul
              variants={copyVariants}
              className="mt-7 flex flex-col gap-3"
            >
              {HIGHLIGHTS.map((highlight) => (
                <motion.li
                  key={highlight}
                  variants={itemVariants}
                  className="flex items-start gap-3 text-sm leading-relaxed text-ink-700 sm:text-base"
                >
                  <span className="mt-0.5 flex h-5 w-5 flex-shrink-0 items-center justify-center rounded-full bg-brand-500 text-white">
                    <CheckIcon className="h-3.5 w-3.5" />
                  </span>
                  <span className="text-pretty">{highlight}</span>
                </motion.li>
              ))}
            </motion.ul>

            <motion.div
              variants={itemVariants}
              className="mt-10 flex flex-col gap-3 sm:flex-row sm:items-center"
            >
              <motion.a
                href="/sample/estimate-sample.pdf"
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center justify-center gap-2 rounded-full bg-ink-950 px-6 py-3 text-sm font-semibold text-white shadow-lg shadow-black/15 transition-colors hover:bg-ink-900"
                whileHover={{ scale: 1.04 }}
                whileTap={{ scale: 0.97 }}
              >
                <DownloadIcon className="text-white" />
                See the full PDF
              </motion.a>
              <p className="text-xs text-ink-400 sm:text-sm">
                3 pages &middot; opens in a new tab
              </p>
            </motion.div>
          </motion.div>
        </div>
      </div>
    </section>
  );
}
