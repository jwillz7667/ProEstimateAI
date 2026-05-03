"use client";

import { motion } from "framer-motion";
import { APP_STORE_URL, PRICING } from "@/lib/constants";

// ---------------------------------------------------------------------------
// Plan feature lists — derived from backend/prisma/seed.ts (Plan.featuresJson)
// ---------------------------------------------------------------------------

const FREE_FEATURES = [
  "5 AI preview generations (lifetime)",
  "Manual estimating & invoicing tools",
  "Project, client & photo library",
  "Watermarked PDFs",
] as const;

const PRO_FEATURES = [
  "20 AI previews / month",
  "20 AI-generated estimates / month",
  "50 quote exports / month",
  "Branded PDFs (your logo + colors)",
  "Client approval share links",
  "Material supplier links in exports",
  "Invoices & proposals",
  "Watermark removed, hi-res preview",
] as const;

const PREMIUM_FEATURES = [
  "Everything in Pro",
  "Unlimited projects, previews & estimates",
  "Priority generation queue",
  "Up to 200 AI previews per day",
  "Up to 500 projects per month",
  "Priority support",
] as const;

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
      className={className ?? "h-5 w-5"}
    >
      <path
        fillRule="evenodd"
        d="M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 0 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z"
        clipRule="evenodd"
      />
    </svg>
  );
}

function CrownIcon({ className }: { className?: string }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
      className={className ?? "h-3.5 w-3.5"}
    >
      <path d="M12 2.5 9 8 4 5l1.5 11h13L20 5l-5 3-3-5.5Z" />
    </svg>
  );
}

// ---------------------------------------------------------------------------
// Animation
// ---------------------------------------------------------------------------

const cardVariants = {
  hidden: { opacity: 0, y: 40 },
  visible: (i: number) => ({
    opacity: 1,
    y: 0,
    transition: {
      delay: i * 0.12,
      duration: 0.6,
      ease: [0.16, 1, 0.3, 1] as const,
    },
  }),
};

// ---------------------------------------------------------------------------
// Section
// ---------------------------------------------------------------------------

export default function Pricing() {
  return (
    <section id="pricing" className="relative overflow-hidden py-24 sm:py-32">
      <div className="mx-auto max-w-7xl px-6 lg:px-8">
        {/* Header */}
        <div className="mx-auto max-w-2xl text-center">
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-brand-600">
            Simple pricing
          </p>
          <h2 className="mt-3 text-4xl font-bold tracking-tight text-balance text-ink-950 sm:text-5xl">
            Pick the plan that fits your week.
          </h2>
          <p className="mt-5 text-lg leading-8 text-pretty text-ink-500">
            Start free to try the workflow. Pro covers a busy solo contractor.
            Premium removes the caps when you&apos;re running multiple crews.
          </p>
        </div>

        {/* Cards */}
        <div className="mx-auto mt-16 grid max-w-7xl grid-cols-1 gap-6 lg:grid-cols-3 lg:gap-6">
          {/* ---- Free ---- */}
          <motion.div
            custom={0}
            variants={cardVariants}
            initial="hidden"
            whileInView="visible"
            viewport={{ once: true, margin: "-80px" }}
            whileHover={{
              y: -6,
              boxShadow:
                "0 20px 60px -12px rgba(0, 0, 0, 0.12), 0 8px 24px -8px rgba(0, 0, 0, 0.08)",
            }}
            transition={{ type: "spring", stiffness: 260, damping: 20 }}
            className="glass relative flex flex-col rounded-2xl p-7 sm:p-8"
          >
            <h3 className="text-2xl font-semibold text-ink-950">Free</h3>
            <p className="mt-1 text-sm text-pretty text-ink-400">
              Try the workflow on your first project.
            </p>

            <div className="mt-6 flex items-baseline gap-x-1">
              <span className="text-5xl font-bold tracking-tight text-ink-950">
                $0
              </span>
              <span className="text-base font-medium text-ink-400">forever</span>
            </div>

            <ul className="mt-8 flex flex-col gap-y-3.5 text-sm leading-6 text-ink-700">
              {FREE_FEATURES.map((feature) => (
                <li key={feature} className="flex items-start gap-x-3">
                  <CheckIcon className="mt-0.5 h-5 w-5 flex-shrink-0 text-brand-500" />
                  <span>{feature}</span>
                </li>
              ))}
            </ul>

            <div className="mt-auto pt-10">
              <a
                href={APP_STORE_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="block w-full rounded-xl border-2 border-ink-200 px-6 py-3.5 text-center text-sm font-semibold text-ink-700 transition-colors duration-200 hover:bg-ink-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink-400"
              >
                Get the app
              </a>
            </div>
          </motion.div>

          {/* ---- Pro ---- */}
          <motion.div
            custom={1}
            variants={cardVariants}
            initial="hidden"
            whileInView="visible"
            viewport={{ once: true, margin: "-80px" }}
            whileHover={{
              y: -6,
              boxShadow:
                "0 20px 60px -12px rgba(255, 146, 48, 0.25), 0 8px 24px -8px rgba(255, 146, 48, 0.15)",
            }}
            transition={{ type: "spring", stiffness: 260, damping: 20 }}
            className="relative flex flex-col rounded-2xl p-7 sm:p-8"
            style={{
              background:
                "linear-gradient(rgba(255,255,255,0.85), rgba(255,255,255,0.85)) padding-box, linear-gradient(135deg, #FF9230, #FFAB58, #FFC580) border-box",
              border: "2px solid transparent",
              backdropFilter: "blur(20px) saturate(180%)",
              WebkitBackdropFilter: "blur(20px) saturate(180%)",
              boxShadow:
                "0 0 40px rgba(255, 146, 48, 0.12), 0 0 80px rgba(255, 146, 48, 0.06)",
            }}
          >
            {/* Badge */}
            <div className="absolute -top-4 left-1/2 -translate-x-1/2">
              <span className="inline-flex items-center rounded-full bg-gradient-to-r from-brand-500 to-brand-600 px-4 py-1.5 text-xs font-bold uppercase tracking-wider text-white shadow-lg shadow-brand-500/30">
                {PRICING.proMonthly.trial}
              </span>
            </div>

            <h3 className="text-2xl font-semibold text-ink-950">Pro</h3>
            <p className="mt-1 text-sm text-pretty text-ink-400">
              For solo contractors quoting weekly.
            </p>

            <div className="mt-6 flex items-baseline gap-x-1">
              <span className="text-5xl font-bold tracking-tight text-ink-950">
                {PRICING.proMonthly.price}
              </span>
              <span className="text-base font-medium text-ink-400">
                {PRICING.proMonthly.cadence}
              </span>
            </div>
            <p className="mt-2 text-sm text-ink-400">
              or {PRICING.proAnnual.price}/yr · save{" "}
              {PRICING.proAnnual.savingsPct}%
            </p>

            <ul className="mt-8 flex flex-col gap-y-3.5 text-sm leading-6 text-ink-700">
              {PRO_FEATURES.map((feature) => (
                <li key={feature} className="flex items-start gap-x-3">
                  <CheckIcon className="mt-0.5 h-5 w-5 flex-shrink-0 text-brand-500" />
                  <span>{feature}</span>
                </li>
              ))}
            </ul>

            <div className="mt-auto pt-10">
              <a
                href={APP_STORE_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="block w-full rounded-xl bg-brand-500 px-6 py-3.5 text-center text-sm font-semibold text-white shadow-lg shadow-brand-500/30 transition-all duration-200 hover:bg-brand-600 hover:shadow-brand-600/40 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-500"
              >
                Start your free trial
              </a>
            </div>
          </motion.div>

          {/* ---- Premium ---- */}
          <motion.div
            custom={2}
            variants={cardVariants}
            initial="hidden"
            whileInView="visible"
            viewport={{ once: true, margin: "-80px" }}
            whileHover={{
              y: -6,
              boxShadow:
                "0 20px 60px -12px rgba(217, 119, 6, 0.30), 0 8px 24px -8px rgba(217, 119, 6, 0.18)",
            }}
            transition={{ type: "spring", stiffness: 260, damping: 20 }}
            className="relative flex flex-col rounded-2xl p-7 sm:p-8"
            style={{
              background:
                "linear-gradient(rgba(20,16,10,0.92), rgba(20,16,10,0.92)) padding-box, linear-gradient(135deg, #D97706, #F59E0B, #FBBF24) border-box",
              border: "2px solid transparent",
              backdropFilter: "blur(20px) saturate(180%)",
              WebkitBackdropFilter: "blur(20px) saturate(180%)",
              boxShadow:
                "0 0 40px rgba(217, 119, 6, 0.18), 0 0 80px rgba(217, 119, 6, 0.10)",
            }}
          >
            {/* Badge */}
            <div className="absolute -top-4 left-1/2 -translate-x-1/2">
              <span className="inline-flex items-center gap-1.5 rounded-full bg-gradient-to-r from-amber-600 to-amber-400 px-4 py-1.5 text-xs font-bold uppercase tracking-wider text-white shadow-lg shadow-amber-500/30">
                <CrownIcon className="h-3.5 w-3.5" />
                Best value
              </span>
            </div>

            <h3 className="text-2xl font-semibold text-white">Premium</h3>
            <p className="mt-1 text-sm text-pretty text-white/60">
              For multi-crew shops running heavy AI.
            </p>

            <div className="mt-6 flex items-baseline gap-x-1">
              <span className="text-5xl font-bold tracking-tight text-white">
                {PRICING.premiumMonthly.price}
              </span>
              <span className="text-base font-medium text-white/60">
                {PRICING.premiumMonthly.cadence}
              </span>
            </div>
            <p className="mt-2 text-sm text-white/60">
              or {PRICING.premiumAnnual.price}/yr · save{" "}
              {PRICING.premiumAnnual.savingsPct}%
            </p>

            <ul className="mt-8 flex flex-col gap-y-3.5 text-sm leading-6 text-white/85">
              {PREMIUM_FEATURES.map((feature) => (
                <li key={feature} className="flex items-start gap-x-3">
                  <CheckIcon className="mt-0.5 h-5 w-5 flex-shrink-0 text-amber-400" />
                  <span>{feature}</span>
                </li>
              ))}
            </ul>

            <div className="mt-auto pt-10">
              <a
                href={APP_STORE_URL}
                target="_blank"
                rel="noopener noreferrer"
                className="block w-full rounded-xl bg-gradient-to-r from-amber-500 to-amber-400 px-6 py-3.5 text-center text-sm font-semibold text-ink-950 shadow-lg shadow-amber-500/30 transition-all duration-200 hover:from-amber-400 hover:to-amber-300 hover:shadow-amber-400/40 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-amber-400"
              >
                Go Premium
              </a>
            </div>
          </motion.div>
        </div>

        <p
          className="mt-10 mx-auto text-center text-xs text-ink-400"
          style={{ maxWidth: "28rem" }}
        >
          Subscriptions auto-renew until canceled. Manage from your Apple ID
          settings. 7-day free trial offered to new Pro subscribers only.
        </p>
      </div>
    </section>
  );
}
