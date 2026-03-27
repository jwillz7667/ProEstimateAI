"use client";

import { useRef } from "react";
import {
  motion,
  useScroll,
  useTransform,
  useInView,
  type MotionValue,
} from "framer-motion";

/* ------------------------------------------------------------------ */
/*  Step data                                                         */
/* ------------------------------------------------------------------ */

interface Step {
  number: number;
  title: string;
  description: string;
}

const STEPS: Step[] = [
  {
    number: 1,
    title: "Upload Photos",
    description:
      "Take or upload photos of the space you want to remodel.",
  },
  {
    number: 2,
    title: "AI Generates Preview",
    description:
      "Our AI creates a photorealistic preview of your renovation in under 60 seconds.",
  },
  {
    number: 3,
    title: "Review Materials",
    description:
      "Get an itemized list of every material needed, with costs and supplier links.",
  },
  {
    number: 4,
    title: "Get Your Estimate",
    description:
      "Choose DIY or professional mode. Export, share, or send to your client.",
  },
];

/* ------------------------------------------------------------------ */
/*  Step card component                                               */
/* ------------------------------------------------------------------ */

function StepCard({
  step,
  index,
  parallaxY,
}: {
  step: Step;
  index: number;
  parallaxY: MotionValue<number>;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-60px" });

  return (
    <motion.div
      ref={ref}
      className="relative flex flex-col items-center text-center"
      /* Parallax: offset each card by a slightly different amount */
      style={{ y: parallaxY }}
      /* Staggered entrance animation */
      initial={{ opacity: 0, y: 40 }}
      animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 40 }}
      transition={{
        duration: 0.6,
        delay: index * 0.15,
        ease: [0.16, 1, 0.3, 1] as const, /* ease-out-expo from design tokens */
      }}
    >
      {/* Step number circle */}
      <div className="relative z-10 flex h-16 w-16 items-center justify-center rounded-full bg-brand-500 shadow-lg shadow-brand-500/25">
        <span className="text-2xl font-bold text-white">{step.number}</span>
      </div>

      {/* Title */}
      <h3 className="mt-6 text-xl font-semibold text-ink-950">
        {step.title}
      </h3>

      {/* Description */}
      <p className="mt-2 max-w-[260px] text-base leading-relaxed text-ink-400">
        {step.description}
      </p>
    </motion.div>
  );
}

/* ------------------------------------------------------------------ */
/*  Dashed connector between steps                                    */
/* ------------------------------------------------------------------ */

function Connector({ index }: { index: number }) {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-40px" });

  return (
    <motion.div
      ref={ref}
      className="relative flex items-center justify-center"
      initial={{ opacity: 0, scale: 0.8 }}
      animate={
        isInView
          ? { opacity: 1, scale: 1 }
          : { opacity: 0, scale: 0.8 }
      }
      transition={{
        duration: 0.5,
        delay: index * 0.15 + 0.1,
        ease: [0.16, 1, 0.3, 1] as const,
      }}
    >
      {/* Horizontal connector (visible on lg+) */}
      <div className="hidden lg:flex items-center">
        <div className="h-px w-16 xl:w-24 border-t-2 border-dashed border-brand-300" />
        <svg
          className="h-4 w-4 -ml-1 text-brand-400"
          viewBox="0 0 16 16"
          fill="currentColor"
          aria-hidden="true"
        >
          <path d="M6.22 3.22a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06-1.06L9.94 8 6.22 4.28a.75.75 0 0 1 0-1.06z" />
        </svg>
      </div>

      {/* Vertical connector (visible on < lg) */}
      <div className="flex flex-col items-center lg:hidden">
        <div className="w-px h-10 border-l-2 border-dashed border-brand-300" />
        <svg
          className="h-4 w-4 -mt-1 text-brand-400"
          viewBox="0 0 16 16"
          fill="currentColor"
          aria-hidden="true"
        >
          <path d="M3.22 6.22a.75.75 0 0 1 1.06 0L8 9.94l3.72-3.72a.75.75 0 1 1 1.06 1.06l-4.25 4.25a.75.75 0 0 1-1.06 0L3.22 7.28a.75.75 0 0 1 0-1.06z" />
        </svg>
      </div>
    </motion.div>
  );
}

/* ------------------------------------------------------------------ */
/*  Section header                                                    */
/* ------------------------------------------------------------------ */

function SectionHeader() {
  const ref = useRef<HTMLDivElement>(null);
  const isInView = useInView(ref, { once: true, margin: "-80px" });

  return (
    <motion.div
      ref={ref}
      className="mx-auto max-w-2xl text-center"
      initial={{ opacity: 0, y: 32 }}
      animate={isInView ? { opacity: 1, y: 0 } : { opacity: 0, y: 32 }}
      transition={{ duration: 0.6, ease: [0.16, 1, 0.3, 1] as const }}
    >
      <h2 className="text-3xl font-bold tracking-tight text-ink-950 sm:text-4xl lg:text-5xl">
        How It Works
      </h2>
      <p className="mt-4 text-lg leading-relaxed text-ink-400 sm:text-xl">
        Four simple steps from photo to professional estimate.
      </p>
    </motion.div>
  );
}

/* ------------------------------------------------------------------ */
/*  Main section                                                      */
/* ------------------------------------------------------------------ */

export default function HowItWorks() {
  const sectionRef = useRef<HTMLElement>(null);

  /* Track the section's scroll progress for parallax */
  const { scrollYProgress } = useScroll({
    target: sectionRef,
    offset: ["start end", "end start"],
  });

  /*
   * Each step gets a slightly different parallax multiplier so the cards
   * appear to shift at different rates as the user scrolls, creating
   * a subtle depth effect. Values are intentionally small to keep
   * the motion comfortable and non-distracting.
   */
  const y0 = useTransform(scrollYProgress, [0, 1], [30, -30]);
  const y1 = useTransform(scrollYProgress, [0, 1], [20, -20]);
  const y2 = useTransform(scrollYProgress, [0, 1], [25, -25]);
  const y3 = useTransform(scrollYProgress, [0, 1], [15, -15]);
  const parallaxValues = [y0, y1, y2, y3];

  return (
    <section
      id="how-it-works"
      ref={sectionRef}
      className="relative overflow-hidden bg-surface-secondary py-24 sm:py-32 lg:py-40"
    >
      {/* Decorative gradient blobs */}
      <div
        className="pointer-events-none absolute -left-40 -top-40 h-[500px] w-[500px] rounded-full bg-brand-100/50 blur-3xl"
        aria-hidden="true"
      />
      <div
        className="pointer-events-none absolute -bottom-40 -right-40 h-[400px] w-[400px] rounded-full bg-brand-50/60 blur-3xl"
        aria-hidden="true"
      />

      <div className="relative mx-auto max-w-7xl px-6 lg:px-8">
        <SectionHeader />

        {/* Steps grid: vertical on mobile, horizontal row on lg+ */}
        <div className="mt-16 flex flex-col items-center gap-8 lg:mt-20 lg:flex-row lg:justify-center lg:gap-0">
          {STEPS.map((step, i) => (
            <div
              key={step.number}
              className="flex flex-col items-center lg:flex-row lg:items-start"
            >
              <StepCard
                step={step}
                index={i}
                parallaxY={parallaxValues[i]}
              />

              {/* Connector after every step except the last */}
              {i < STEPS.length - 1 && <Connector index={i} />}
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
