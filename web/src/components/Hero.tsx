"use client";

import { useEffect, useRef, useState } from "react";
import { motion, useReducedMotion, type Variants } from "framer-motion";
import { APP_STORE_URL } from "@/lib/constants";

// ---------------------------------------------------------------------------
// Animation variants
// ---------------------------------------------------------------------------

const containerVariants: Variants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: { staggerChildren: 0.12, delayChildren: 0.15 },
  },
};

const fadeInUp: Variants = {
  hidden: { opacity: 0, y: 24 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.6, ease: [0.16, 1, 0.3, 1] as const },
  },
};

const mediaEnter: Variants = {
  hidden: { opacity: 0, y: 40, scale: 0.96 },
  visible: {
    opacity: 1,
    y: 0,
    scale: 1,
    transition: { duration: 0.8, ease: [0.16, 1, 0.3, 1] as const, delay: 0.25 },
  },
};

// ---------------------------------------------------------------------------
// Inline icons
// ---------------------------------------------------------------------------

function SparkleIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      width="14"
      height="14"
      viewBox="0 0 16 16"
      fill="none"
      aria-hidden="true"
    >
      <path
        d="M8 0C8 0 8.75 5.25 11 8C8.75 10.75 8 16 8 16C8 16 7.25 10.75 5 8C7.25 5.25 8 0 8 0Z"
        fill="currentColor"
      />
    </svg>
  );
}

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

function PlayIcon({ className }: { className?: string }) {
  return (
    <svg
      className={className}
      width="18"
      height="18"
      viewBox="0 0 20 20"
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="M6.5 4.5L15 10L6.5 15.5V4.5Z" />
    </svg>
  );
}

// ---------------------------------------------------------------------------
// Demo video player
// ---------------------------------------------------------------------------

/**
 * Glass-card chrome around the 4:3 demo clip. Autoplay / muted / loop /
 * playsInline so iOS Safari plays inline; pauses on the poster when the
 * user prefers reduced motion. Falls back to the poster image if the
 * video fails to load.
 */
function DemoFrame() {
  const prefersReducedMotion = useReducedMotion();
  const videoRef = useRef<HTMLVideoElement>(null);
  const [hasError, setHasError] = useState(false);

  useEffect(() => {
    const node = videoRef.current;
    if (!node) return;
    if (prefersReducedMotion) {
      node.pause();
    } else {
      // Some Safari versions need an explicit play() after the metadata
      // loads even when autoplay is set, hence the catch-and-ignore.
      node.play().catch(() => {
        /* autoplay blocked — poster stays visible */
      });
    }
  }, [prefersReducedMotion]);

  return (
    <div className="relative mx-auto w-full max-w-[480px] sm:max-w-[560px] lg:max-w-none">
      {/* Soft glow halo */}
      <div
        aria-hidden="true"
        className="absolute -inset-10 -z-10 rounded-[2.5rem] bg-white/25 blur-3xl"
      />

      {/* Glass bezel */}
      <div className="relative aspect-[4/3] overflow-hidden rounded-[1.75rem] bg-ink-950/90 p-2 shadow-2xl shadow-black/40 ring-1 ring-white/15 backdrop-blur-md sm:rounded-[2rem] sm:p-2.5">
        {/* Inner surface */}
        <div className="relative h-full w-full overflow-hidden rounded-[1.4rem] bg-ink-900 sm:rounded-[1.6rem]">
          {hasError ? (
            <img
              src="/video/hero-demo-poster.jpg"
              alt="ProEstimate AI app demo"
              className="absolute inset-0 h-full w-full object-cover"
              loading="eager"
            />
          ) : (
            <video
              ref={videoRef}
              className="absolute inset-0 h-full w-full object-cover"
              autoPlay
              loop
              muted
              playsInline
              preload="metadata"
              poster="/video/hero-demo-poster.jpg"
              onError={() => setHasError(true)}
              aria-label="ProEstimate AI app demo: photo upload to AI preview to estimate"
            >
              <source src="/video/hero-demo.webm" type="video/webm" />
              <source src="/video/hero-demo.mp4" type="video/mp4" />
            </video>
          )}

          {/* Subtle top highlight for glass reflection */}
          <div
            aria-hidden="true"
            className="pointer-events-none absolute inset-x-0 top-0 h-24 bg-gradient-to-b from-white/15 to-transparent"
          />
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

export default function Hero() {
  return (
    <section className="relative isolate overflow-hidden bg-gradient-to-b from-brand-500 via-brand-500 to-brand-600 pt-28 pb-16 sm:pt-32 sm:pb-20 lg:pt-40 lg:pb-32">
      {/* Decorative blurred orbs */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -top-24 -left-24 h-[420px] w-[420px] rounded-full bg-white/15 blur-3xl"
      />
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -bottom-32 -right-32 h-[460px] w-[460px] rounded-full bg-brand-300/30 blur-3xl"
      />

      <motion.div
        className="relative z-10 mx-auto grid max-w-7xl grid-cols-1 items-center gap-12 px-6 sm:px-8 lg:grid-cols-2 lg:gap-14 lg:px-12"
        variants={containerVariants}
        initial="hidden"
        animate="visible"
      >
        {/* ---- Left: copy + CTAs ---- */}
        <div className="min-w-0 text-center lg:text-left">
          <motion.div
            className="mb-6 inline-flex items-center gap-2 rounded-full bg-white/15 px-4 py-1.5 text-xs font-semibold uppercase tracking-wider text-white backdrop-blur-sm ring-1 ring-white/20"
            variants={fadeInUp}
          >
            <SparkleIcon className="text-white" />
            AI-powered remodel previews
          </motion.div>

          <motion.h1
            className="text-5xl font-bold leading-[1.05] tracking-tight text-balance text-white sm:text-6xl"
            variants={fadeInUp}
          >
            See the remodel{" "}
            <span className="text-ink-950">before you build it.</span>
          </motion.h1>

          <motion.p
            className="mx-auto mt-6 text-lg leading-relaxed text-pretty text-white/90 sm:text-xl lg:mx-0"
            variants={fadeInUp}
          >
            Snap a photo of any room, roof, or yard. ProEstimate AI returns a
            photoreal preview, an itemized material list, and a contractor-grade
            estimate &mdash; in under a minute.
          </motion.p>

          <motion.div
            className="mt-10 flex flex-col items-center justify-center gap-3 sm:flex-row lg:justify-start"
            variants={fadeInUp}
          >
            <motion.a
              href={APP_STORE_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center justify-center gap-2 rounded-full bg-white px-7 py-3.5 text-base font-semibold text-ink-950 shadow-lg shadow-black/15 transition-colors hover:bg-white/95"
              whileHover={{ scale: 1.04 }}
              whileTap={{ scale: 0.97 }}
            >
              <AppleIcon className="text-ink-950" />
              Download on App Store
            </motion.a>

            <motion.a
              href="#how-it-works"
              className="inline-flex items-center justify-center gap-2 rounded-full border-2 border-white/80 px-7 py-3.5 text-base font-semibold text-white transition-colors hover:bg-white/10"
              whileHover={{ scale: 1.04 }}
              whileTap={{ scale: 0.97 }}
            >
              <PlayIcon className="text-white" />
              See how it works
            </motion.a>
          </motion.div>

          <motion.p
            className="mt-6 text-sm text-white/75"
            variants={fadeInUp}
          >
            Free to start &middot; no credit card &middot; iOS 17+
          </motion.p>
        </div>

        {/* ---- Right: glass-framed demo video ---- */}
        <motion.div variants={mediaEnter} className="min-w-0">
          <DemoFrame />
        </motion.div>
      </motion.div>
    </section>
  );
}
