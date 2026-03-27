"use client";

import { motion, type Variants } from "framer-motion";

// ---------------------------------------------------------------------------
// Animation Variants
// ---------------------------------------------------------------------------

/** Container orchestrates staggered children entrance */
const containerVariants: Variants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: {
      staggerChildren: 0.12,
      delayChildren: 0.1,
    },
  },
};

/** Fade-in-up for text and button children */
const fadeInUp: Variants = {
  hidden: { opacity: 0, y: 32 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.6, ease: [0.16, 1, 0.3, 1] as const },
  },
};

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const APP_STORE_URL = "https://apps.apple.com/app/proestimate-ai/id0000000000";

// ---------------------------------------------------------------------------
// Decorative Floating Circles
// ---------------------------------------------------------------------------

interface FloatingCircle {
  size: number;
  top: string;
  left: string;
  opacity: number;
  delay: number;
}

const FLOATING_CIRCLES: FloatingCircle[] = [
  { size: 320, top: "-10%", left: "-5%", opacity: 0.06, delay: 0 },
  { size: 200, top: "60%", left: "85%", opacity: 0.08, delay: 0.4 },
  { size: 140, top: "15%", left: "75%", opacity: 0.05, delay: 0.8 },
  { size: 100, top: "70%", left: "10%", opacity: 0.07, delay: 1.2 },
  { size: 80, top: "30%", left: "50%", opacity: 0.04, delay: 0.6 },
];

// ---------------------------------------------------------------------------
// Apple Icon (inline SVG)
// ---------------------------------------------------------------------------

function AppleIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      width="18"
      height="18"
      viewBox="0 0 384 512"
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-27.1-46.9-42.2-83.7-45.3-35.1-3-73.5 20.7-87.6 20.7-14.8 0-49-19.7-74.4-19.7C63.1 141.2 0 184.8 0 273.5c0 26.2 4.8 53.3 14.4 81.2 12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-62.1 24-72.5-24 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z" />
    </svg>
  );
}

// ---------------------------------------------------------------------------
// CTA Component
// ---------------------------------------------------------------------------

export default function CTA() {
  return (
    <section
      id="get-started"
      className="relative overflow-hidden bg-gradient-to-br from-brand-500 to-brand-600 py-24 sm:py-32"
    >
      {/* Floating decorative circles */}
      {FLOATING_CIRCLES.map((circle, i) => (
        <motion.div
          key={i}
          className="pointer-events-none absolute rounded-full bg-white"
          style={{
            width: circle.size,
            height: circle.size,
            top: circle.top,
            left: circle.left,
            opacity: 0,
          }}
          animate={{
            opacity: [0, circle.opacity, 0],
            scale: [0.8, 1, 0.8],
            y: [0, -20, 0],
          }}
          transition={{
            duration: 6,
            repeat: Infinity,
            delay: circle.delay,
            ease: "easeInOut",
          }}
        />
      ))}

      {/* Subtle radial glow behind content */}
      <div
        className="pointer-events-none absolute inset-0"
        style={{
          background:
            "radial-gradient(ellipse 60% 50% at 50% 50%, rgba(255,255,255,0.12) 0%, transparent 70%)",
        }}
      />

      {/* Content */}
      <motion.div
        className="relative z-10 mx-auto max-w-4xl px-6 text-center sm:px-8 lg:px-12"
        variants={containerVariants}
        initial="hidden"
        whileInView="visible"
        viewport={{ once: true, amount: 0.4 }}
      >
        {/* Heading */}
        <motion.h2
          className="text-4xl font-bold leading-tight tracking-tight text-white md:text-5xl lg:text-6xl"
          variants={fadeInUp}
        >
          Ready to Transform Your Next Project?
        </motion.h2>

        {/* Subtext */}
        <motion.p
          className="mx-auto mt-6 max-w-2xl text-lg leading-relaxed text-white/85 md:text-xl"
          variants={fadeInUp}
        >
          Join thousands of contractors and homeowners using AI to estimate
          smarter.
        </motion.p>

        {/* CTA buttons */}
        <motion.div
          className="mt-10 flex flex-col items-center justify-center gap-4 sm:flex-row"
          variants={fadeInUp}
        >
          {/* Primary — Download on App Store */}
          <motion.a
            href={APP_STORE_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-2.5 rounded-full bg-white px-8 py-4 text-base font-semibold text-brand-600 shadow-lg transition-colors duration-200 hover:bg-white/95"
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.97 }}
          >
            <AppleIcon />
            Download on App Store
          </motion.a>

          {/* Secondary — Try Web Demo */}
          <motion.a
            href="#demo"
            className="inline-flex items-center gap-2 rounded-full border-2 border-white px-8 py-4 text-base font-semibold text-white transition-colors duration-200 hover:bg-white/10"
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.97 }}
          >
            Try Web Demo
          </motion.a>
        </motion.div>
      </motion.div>
    </section>
  );
}
