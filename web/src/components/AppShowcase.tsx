"use client";

import { motion, type Variants } from "framer-motion";
import { Swiper, SwiperSlide } from "swiper/react";
import { EffectCoverflow, Pagination, Autoplay } from "swiper/modules";

import "swiper/css";
import "swiper/css/effect-coverflow";
import "swiper/css/pagination";

// ---------------------------------------------------------------------------
// Slide data — every screen the carousel ships with is a real screenshot
// of the iOS app under /public/screenshots
// ---------------------------------------------------------------------------

interface AppScreen {
  title: string;
  caption: string;
  screenshot: string;
}

const APP_SCREENS: AppScreen[] = [
  {
    title: "Dashboard",
    caption: "Active projects, recent generations, and one-tap new project.",
    screenshot: "/screenshots/dashboard.jpg",
  },
  {
    title: "Projects",
    caption: "Every job at a glance — drafts, estimate-ready, in-flight, archived.",
    screenshot: "/screenshots/projects.jpg",
  },
  {
    title: "Project type",
    caption: "Nine categories with prompt presets tuned for the AI.",
    screenshot: "/screenshots/category-picker.jpg",
  },
  {
    title: "Photos & vision",
    caption: "Up to 10 reference photos plus a style direction or custom prompt.",
    screenshot: "/screenshots/style-direction.jpg",
  },
  {
    title: "Project details",
    caption: "Optional area, lot size, and budget tune the AI's quantity math.",
    screenshot: "/screenshots/project-details.jpg",
  },
  {
    title: "AI preview",
    caption: "Photoreal before/after with pinch-to-zoom and slide-to-compare.",
    screenshot: "/screenshots/ai-preview.jpg",
  },
  {
    title: "Estimate ready",
    caption: "Materials, labor, and markup priced — sign off in seconds.",
    screenshot: "/screenshots/estimate-ready.jpg",
  },
  {
    title: "Materials",
    caption: "Each line linked to a real supplier with a one-tap price-verify.",
    screenshot: "/screenshots/materials.jpg",
  },
  {
    title: "Plans",
    caption: "Free, Pro, or Premium — toggle monthly or annual on the same sheet.",
    screenshot: "/screenshots/paywall.jpg",
  },
];

// ---------------------------------------------------------------------------
// Animation variants
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
// Screenshot card with phone-frame chrome
// ---------------------------------------------------------------------------

function ScreenshotCard({ screen }: { screen: AppScreen }) {
  return (
    <figure className="flex flex-col items-center gap-5">
      <div className="relative w-full max-w-[260px] sm:max-w-[280px]">
        <div
          aria-hidden="true"
          className="absolute -inset-4 -z-10 rounded-full bg-brand-200/30 blur-2xl"
        />
        <div className="relative w-full rounded-[2.4rem] bg-ink-950 p-[6px] shadow-2xl ring-1 ring-white/10 sm:p-[7px]">
          <div className="relative aspect-[1206/2622] w-full overflow-hidden rounded-[2.1rem] bg-ink-950">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={screen.screenshot}
              alt={`${screen.title} screen of the ProEstimate AI iOS app — ${screen.caption}`}
              loading="lazy"
              decoding="async"
              width={1206}
              height={2622}
              className="block h-full w-full object-cover"
            />
          </div>
        </div>
      </div>
      <figcaption className="max-w-[260px] text-center">
        <p className="text-sm font-semibold text-ink-950">{screen.title}</p>
        <p className="mt-1 text-xs leading-relaxed text-pretty text-ink-400">
          {screen.caption}
        </p>
      </figcaption>
    </figure>
  );
}

// ---------------------------------------------------------------------------
// Section
// ---------------------------------------------------------------------------

export default function AppShowcase() {
  return (
    <section
      id="showcase"
      className="relative overflow-hidden bg-ink-50 py-24 sm:py-32"
    >
      <motion.div
        className="mx-auto max-w-7xl px-6 sm:px-8 lg:px-12"
        variants={sectionVariants}
        initial="hidden"
        whileInView="visible"
        viewport={{ once: true, amount: 0.2 }}
      >
        <div className="mb-16 text-center">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-brand-600">
            The whole app, on every screen
          </p>
          <h2 className="mt-3 text-4xl font-bold tracking-tight text-balance text-ink-950 sm:text-5xl">
            Designed for the field. Built like Apple software.
          </h2>
          <p className="mx-auto mt-5 max-w-2xl text-lg text-pretty text-ink-500">
            Apple Liquid Glass surfaces, type that scales for accessibility,
            full Dark Mode and Spanish localization out of the box.
          </p>
        </div>

        <Swiper
          modules={[EffectCoverflow, Pagination, Autoplay]}
          effect="coverflow"
          grabCursor
          centeredSlides
          slidesPerView="auto"
          loop
          autoplay={{
            delay: 4500,
            disableOnInteraction: false,
            pauseOnMouseEnter: true,
          }}
          coverflowEffect={{
            rotate: 18,
            stretch: 0,
            depth: 140,
            modifier: 1,
            slideShadows: false,
          }}
          pagination={{ clickable: true }}
          className="!overflow-visible !pb-14"
        >
          {APP_SCREENS.map((screen) => (
            <SwiperSlide
              key={screen.title}
              className="!w-[260px] sm:!w-[280px] lg:!w-[300px]"
            >
              <ScreenshotCard screen={screen} />
            </SwiperSlide>
          ))}
        </Swiper>
      </motion.div>
    </section>
  );
}
