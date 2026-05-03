"use client";

import { useRef } from "react";
import { motion, useInView, type Variants } from "framer-motion";

// ---------------------------------------------------------------------------
// Step data — pairs each workflow stage with a real app screenshot
// ---------------------------------------------------------------------------

interface Step {
  number: number;
  eyebrow: string;
  title: string;
  description: string;
  screenshot: string;
  alt: string;
}

const STEPS: Step[] = [
  {
    number: 1,
    eyebrow: "Pick the project",
    title: "Choose what you're estimating.",
    description:
      "Kitchen, bath, roof, siding, painting, landscaping — nine project types, each with prompt presets tuned for the AI so you get a useful preview on the first shot.",
    screenshot: "/screenshots/category-picker.jpg",
    alt: "ProEstimate AI category picker with kitchen, bath, roofing, painting, siding, room remodel, exterior, and landscaping",
  },
  {
    number: 2,
    eyebrow: "Snap a photo",
    title: "Upload up to 10 reference photos.",
    description:
      "Take photos in-app or pull from your library. Drop a style direction or write a custom prompt — the AI uses both to compose the preview.",
    screenshot: "/screenshots/style-direction.jpg",
    alt: "ProEstimate AI photo upload screen with style direction picker",
  },
  {
    number: 3,
    eyebrow: "Watch it generate",
    title: "Photoreal preview in under 60 seconds.",
    description:
      "Nano Banana 2 produces a before/after preview that holds the layout while showing the renovation. Slide to compare, pinch to zoom, double-tap to reset.",
    screenshot: "/screenshots/ai-preview.jpg",
    alt: "Before/after AI-generated landscape install with cobble path and retaining wall",
  },
  {
    number: 4,
    eyebrow: "Send the proposal",
    title: "Hand off a contractor-grade estimate.",
    description:
      "Materials and labor priced automatically, every line linked to a supplier. Edit line items, apply your branding, send a client-approval link, then convert to invoice.",
    screenshot: "/screenshots/estimate-ready.jpg",
    alt: "Garage Build-Out project with AI Estimate Ready showing $4,957 total",
  },
];

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

const rowEnter: Variants = {
  hidden: { opacity: 0, y: 40 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.7, ease: [0.16, 1, 0.3, 1] as const },
  },
};

// ---------------------------------------------------------------------------
// Step row — copy + phone screenshot, alternating sides
// ---------------------------------------------------------------------------

function StepRow({ step, reverse }: { step: Step; reverse: boolean }) {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-80px" });

  return (
    <motion.div
      ref={ref}
      variants={rowEnter}
      initial="hidden"
      animate={isInView ? "visible" : "hidden"}
      className={`grid grid-cols-1 items-center gap-10 lg:grid-cols-2 lg:gap-16 ${
        reverse ? "lg:[&>*:first-child]:order-2" : ""
      }`}
    >
      {/* Copy column */}
      <div className="min-w-0">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-full bg-brand-500 text-base font-bold text-white shadow-md shadow-brand-500/25">
            {step.number}
          </div>
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-brand-600">
            {step.eyebrow}
          </p>
        </div>
        <h3 className="mt-5 text-3xl font-bold tracking-tight text-balance text-ink-950 sm:text-4xl">
          {step.title}
        </h3>
        <p className="mt-4 text-base leading-relaxed text-pretty text-ink-500 sm:text-lg">
          {step.description}
        </p>
      </div>

      {/* Phone screenshot */}
      <div className="relative mx-auto w-full max-w-[280px] sm:max-w-[320px]">
        <div
          aria-hidden="true"
          className="absolute -inset-6 -z-10 rounded-full bg-brand-100/60 blur-3xl"
        />
        <div className="relative w-full rounded-[2.5rem] bg-ink-950 p-[6px] shadow-xl shadow-black/15 ring-1 ring-black/5 sm:p-[7px]">
          <div className="relative aspect-[1206/2622] w-full overflow-hidden rounded-[2.2rem] bg-ink-950">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={step.screenshot}
              alt={step.alt}
              loading="lazy"
              decoding="async"
              width={1206}
              height={2622}
              className="block h-full w-full object-cover"
            />
          </div>
        </div>
      </div>
    </motion.div>
  );
}

// ---------------------------------------------------------------------------
// Section
// ---------------------------------------------------------------------------

export default function HowItWorks() {
  return (
    <section
      id="how-it-works"
      className="relative overflow-hidden bg-surface-secondary py-24 sm:py-32 lg:py-36"
    >
      {/* Decorative blobs */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -left-40 -top-40 h-[500px] w-[500px] rounded-full bg-brand-100/50 blur-3xl"
      />
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -bottom-40 -right-40 h-[400px] w-[400px] rounded-full bg-brand-50/60 blur-3xl"
      />

      <div className="relative mx-auto max-w-7xl px-6 lg:px-8">
        {/* Section header */}
        <motion.div
          variants={headerVariants}
          initial="hidden"
          whileInView="visible"
          viewport={{ once: true, margin: "-80px" }}
          className="mx-auto max-w-2xl text-center"
        >
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-brand-600">
            How it works
          </p>
          <h2 className="mt-3 text-4xl font-bold tracking-tight text-balance text-ink-950 sm:text-5xl">
            From a phone in your pocket to a signed proposal.
          </h2>
          <p className="mt-5 text-lg leading-relaxed text-pretty text-ink-500">
            Four steps, one app, no spreadsheets. The whole flow is designed
            for the field — gloves on, sun in your eyes, client waiting.
          </p>
        </motion.div>

        {/* Step rows */}
        <div className="mt-20 flex flex-col gap-24 lg:gap-32">
          {STEPS.map((step, i) => (
            <StepRow key={step.number} step={step} reverse={i % 2 === 1} />
          ))}
        </div>
      </div>
    </section>
  );
}
