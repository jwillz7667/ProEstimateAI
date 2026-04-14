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
  screenshot: string;
}

const APP_SCREENS: AppScreen[] = [
  {
    title: "Dashboard",
    screenshot: "/screenshots/dashboard.png",
  },
  {
    title: "Project Types",
    screenshot: "/screenshots/project-type.png",
  },
  {
    title: "Project Details",
    screenshot: "/screenshots/project-details.png",
  },
  {
    title: "AI Generating",
    screenshot: "/screenshots/ai-generating.png",
  },
  {
    title: "AI Preview",
    screenshot: "/screenshots/ai-preview.png",
  },
];

// ---------------------------------------------------------------------------
// Screenshot Card
// ---------------------------------------------------------------------------

function ScreenshotCard({ screen }: { screen: AppScreen }) {
  return (
    <div className="relative overflow-hidden rounded-[2rem] bg-ink-950 shadow-2xl ring-1 ring-white/10">
      <img
        src={screen.screenshot}
        alt={`${screen.title} screen`}
        className="block w-full"
        loading="lazy"
      />
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
            ProEstimate workflow.
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
            rotate: 20,
            stretch: 0,
            depth: 120,
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
