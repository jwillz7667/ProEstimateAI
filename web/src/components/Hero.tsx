"use client";

import { motion, type Variants } from "framer-motion";

// ---------------------------------------------------------------------------
// Animation Variants
// ---------------------------------------------------------------------------

/** Parent container — orchestrates staggered children animations */
const containerVariants: Variants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.15,
      delayChildren: 0.2,
    },
  },
};

/** Fade-in-up for each text/button child */
const fadeInUp: Variants = {
  hidden: { opacity: 0, y: 24 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.6, ease: [0.16, 1, 0.3, 1] as const },
  },
};

/** Scale-in for the stats cards */
const scaleIn: Variants = {
  hidden: { opacity: 0, scale: 0.85 },
  visible: {
    opacity: 1,
    scale: 1,
    transition: { duration: 0.5, ease: [0.16, 1, 0.3, 1] as const },
  },
};

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

/** Sparkle SVG icon used inside the badge */
function SparkleIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      width="16"
      height="16"
      viewBox="0 0 16 16"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
    >
      <path
        d="M8 0C8 0 8.75 5.25 11 8C8.75 10.75 8 16 8 16C8 16 7.25 10.75 5 8C7.25 5.25 8 0 8 0Z"
        fill="currentColor"
      />
      <path
        d="M2 6C2 6 3.5 7.25 4.5 8C3.5 8.75 2 10 2 10C2 10 3.5 8.75 4.5 8C3.5 7.25 2 6 2 6Z"
        fill="currentColor"
        opacity="0.6"
      />
      <path
        d="M14 6C14 6 12.5 7.25 11.5 8C12.5 8.75 14 10 14 10C14 10 12.5 8.75 11.5 8C12.5 7.25 14 6 14 6Z"
        fill="currentColor"
        opacity="0.6"
      />
    </svg>
  );
}

/** Play triangle icon for the "Watch Demo" button */
function PlayIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      width="20"
      height="20"
      viewBox="0 0 20 20"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
    >
      <path
        d="M6.5 4.5L15 10L6.5 15.5V4.5Z"
        fill="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

// ---------------------------------------------------------------------------
// Stats data
// ---------------------------------------------------------------------------

interface Stat {
  value: string;
  label: string;
}

const stats: Stat[] = [
  { value: "10K+", label: "Projects" },
  { value: "4.9\u2605", label: "Rating" },
  { value: "60sec", label: "Estimates" },
];

// ---------------------------------------------------------------------------
// Hero Component
// ---------------------------------------------------------------------------

export default function Hero() {
  return (
    <section className="relative min-h-screen flex items-center justify-center overflow-hidden">
      {/* Content layer — sits above the WebGL canvas (z-0) */}
      <motion.div
        className="relative z-10 mx-auto max-w-6xl px-6 py-24 text-center sm:px-8 lg:px-12"
        variants={containerVariants}
        initial="hidden"
        animate="visible"
      >
        {/* ---- Animated badge ---- */}
        <motion.div className="mb-8 flex justify-center" variants={fadeInUp}>
          <span className="glass-brand inline-flex items-center gap-2 rounded-full px-5 py-2 text-sm font-medium text-brand-600">
            <SparkleIcon className="text-brand-500" />
            Powered by AI
          </span>
        </motion.div>

        {/* ---- Main headline ---- */}
        <motion.h1
          className="text-5xl font-bold leading-tight tracking-tight text-gray-900 md:text-7xl"
          variants={fadeInUp}
        >
          See Your Remodel{" "}
          <span className="text-gradient">Before You Build</span>
        </motion.h1>

        {/* ---- Sub-headline ---- */}
        <motion.p
          className="mx-auto mt-6 max-w-2xl text-lg leading-relaxed text-gray-600 md:text-xl"
          variants={fadeInUp}
        >
          Upload a photo. Get an AI-generated preview of your renovation, a full
          materials list with supplier links, and a professional cost estimate
          &mdash; in minutes, not days.
        </motion.p>

        {/* ---- CTA buttons ---- */}
        <motion.div
          className="mt-10 flex flex-col items-center justify-center gap-4 sm:flex-row"
          variants={fadeInUp}
        >
          {/* Primary CTA */}
          <motion.a
            href="#get-started"
            className="glow-brand inline-flex items-center rounded-full bg-brand-500 px-8 py-4 text-base font-semibold text-white shadow-lg transition-colors hover:bg-brand-600"
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.97 }}
          >
            Get Started Free
          </motion.a>

          {/* Secondary CTA — glass morphism */}
          <motion.a
            href="#demo"
            className="glass inline-flex items-center gap-2 rounded-full px-8 py-4 text-base font-semibold text-gray-800 transition-colors hover:bg-white/90"
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.97 }}
          >
            <PlayIcon className="text-brand-500" />
            Watch Demo
          </motion.a>
        </motion.div>

        {/* ---- Floating stats bar ---- */}
        <motion.div
          className="mt-16 flex flex-col items-center justify-center gap-4 sm:flex-row sm:gap-6"
          variants={containerVariants}
          initial="hidden"
          whileInView="visible"
          viewport={{ once: true, amount: 0.6 }}
        >
          {stats.map((stat) => (
            <motion.div
              key={stat.label}
              className="glass flex min-w-[140px] flex-col items-center rounded-2xl px-6 py-4"
              variants={scaleIn}
            >
              <span className="text-2xl font-bold text-brand-600">
                {stat.value}
              </span>
              <span className="mt-1 text-sm text-gray-500">{stat.label}</span>
            </motion.div>
          ))}
        </motion.div>
      </motion.div>
    </section>
  );
}
