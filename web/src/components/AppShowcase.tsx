"use client";

import { motion, type Variants } from "framer-motion";
import { Swiper, SwiperSlide } from "swiper/react";
import { EffectCoverflow, Pagination } from "swiper/modules";

import "swiper/css";
import "swiper/css/effect-coverflow";
import "swiper/css/pagination";

// ---------------------------------------------------------------------------
// Animation Variants
// ---------------------------------------------------------------------------

const sectionVariants: Variants = {
  hidden: { opacity: 0, y: 40 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.7, ease: [0.16, 1, 0.3, 1] as const },
  },
};

// ---------------------------------------------------------------------------
// Slide Data
// ---------------------------------------------------------------------------

interface AppScreen {
  title: string;
  gradient: string;
  features: string[];
  /** Icon emoji rendered at the top of the card */
  icon: string;
}

const APP_SCREENS: AppScreen[] = [
  {
    title: "Dashboard",
    gradient: "from-brand-500 to-brand-700",
    icon: "\u{1F4CA}",
    features: [
      "Active project overview",
      "Revenue & expense tracking",
      "Quick-action shortcuts",
    ],
  },
  {
    title: "AI Preview",
    gradient: "from-brand-400 to-brand-600",
    icon: "\u{2728}",
    features: [
      "Photo-to-render in seconds",
      "Multiple style options",
      "Before & after comparison",
    ],
  },
  {
    title: "Materials",
    gradient: "from-brand-600 to-brand-800",
    icon: "\u{1F9F1}",
    features: [
      "AI-suggested materials",
      "Supplier links & pricing",
      "Quantity calculator",
    ],
  },
  {
    title: "Estimate",
    gradient: "from-brand-500 to-brand-700",
    icon: "\u{1F4B0}",
    features: [
      "Itemized cost breakdown",
      "Labor & material totals",
      "One-tap PDF export",
    ],
  },
  {
    title: "Proposal",
    gradient: "from-brand-400 to-brand-600",
    icon: "\u{1F4DD}",
    features: [
      "Professional templates",
      "Client share link",
      "E-signature ready",
    ],
  },
];

// ---------------------------------------------------------------------------
// Screenshot Card
// ---------------------------------------------------------------------------

function ScreenshotCard({ screen }: { screen: AppScreen }) {
  return (
    <div
      className={`relative flex aspect-[9/19] w-full flex-col overflow-hidden rounded-2xl bg-gradient-to-b ${screen.gradient} p-6 shadow-2xl`}
    >
      {/* Simulated status bar */}
      <div className="mb-6 flex items-center justify-between">
        <div className="h-2 w-10 rounded-full bg-white/20" />
        <div className="h-2 w-6 rounded-full bg-white/20" />
      </div>

      {/* Icon */}
      <div className="mb-3 text-4xl" aria-hidden="true">
        {screen.icon}
      </div>

      {/* Screen title */}
      <h3 className="mb-4 text-xl font-bold text-white">{screen.title}</h3>

      {/* Feature bullets */}
      <ul className="flex flex-col gap-2.5">
        {screen.features.map((feature) => (
          <li key={feature} className="flex items-start gap-2 text-sm text-white/85">
            <span className="mt-0.5 block h-1.5 w-1.5 shrink-0 rounded-full bg-white/60" />
            {feature}
          </li>
        ))}
      </ul>

      {/* Decorative bottom elements — simulated UI skeleton */}
      <div className="mt-auto flex flex-col gap-3 pt-8">
        <div className="h-10 w-full rounded-xl bg-white/15" />
        <div className="flex gap-2">
          <div className="h-10 flex-1 rounded-xl bg-white/10" />
          <div className="h-10 flex-1 rounded-xl bg-white/10" />
        </div>
        <div className="h-3 w-3/4 rounded-full bg-white/10" />
      </div>

      {/* Home indicator */}
      <div className="mx-auto mt-4 h-1 w-28 rounded-full bg-white/25" />
    </div>
  );
}

// ---------------------------------------------------------------------------
// AppShowcase Component
// ---------------------------------------------------------------------------

export default function AppShowcase() {
  return (
    <section className="relative overflow-hidden bg-ink-50 py-24 sm:py-32">
      <motion.div
        className="mx-auto max-w-7xl px-6 sm:px-8 lg:px-12"
        variants={sectionVariants}
        initial="hidden"
        whileInView="visible"
        viewport={{ once: true, amount: 0.2 }}
      >
        {/* Section header */}
        <div className="mb-16 text-center">
          <h2 className="text-4xl font-bold tracking-tight text-ink-950 md:text-5xl">
            See It{" "}
            <span className="text-gradient">In Action</span>
          </h2>
          <p className="mx-auto mt-4 max-w-2xl text-lg text-ink-500">
            From photo upload to polished proposal, experience the complete
            ProEstimate AI workflow.
          </p>
        </div>

        {/* Swiper Carousel */}
        <Swiper
          modules={[EffectCoverflow, Pagination]}
          effect="coverflow"
          grabCursor
          centeredSlides
          slidesPerView="auto"
          coverflowEffect={{
            rotate: 30,
            stretch: 0,
            depth: 100,
            modifier: 1,
            slideShadows: false,
          }}
          pagination={{ clickable: true }}
          className="!overflow-visible !pb-14"
        >
          {APP_SCREENS.map((screen) => (
            <SwiperSlide
              key={screen.title}
              className="!w-[220px] sm:!w-[260px] lg:!w-[280px]"
            >
              <ScreenshotCard screen={screen} />
            </SwiperSlide>
          ))}
        </Swiper>
      </motion.div>
    </section>
  );
}
