"use client";

import { motion } from "framer-motion";

// ---------------------------------------------------------------------------
// Plan feature lists
// ---------------------------------------------------------------------------

const FREE_FEATURES = [
  "3 AI preview generations",
  "3 estimate exports",
  "Basic material suggestions",
  "Single project",
] as const;

const PRO_FEATURES = [
  "Unlimited AI generations",
  "Unlimited exports",
  "Priority AI processing",
  "Unlimited projects",
  "Proposals & invoicing",
  "Supplier links on materials",
  "Priority support",
] as const;

// ---------------------------------------------------------------------------
// Checkmark icon (inline SVG to avoid external dependency)
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

// ---------------------------------------------------------------------------
// Animation variants
// ---------------------------------------------------------------------------

const cardVariants = {
  hidden: { opacity: 0, y: 40 },
  visible: (i: number) => ({
    opacity: 1,
    y: 0,
    transition: {
      delay: i * 0.15,
      duration: 0.6,
      ease: [0.16, 1, 0.3, 1] as const, // ease-out-expo from design tokens
    },
  }),
};

// ---------------------------------------------------------------------------
// Pricing Section
// ---------------------------------------------------------------------------

export default function Pricing() {
  return (
    <section
      id="pricing"
      className="relative overflow-hidden py-24 sm:py-32"
    >
      {/* Section header */}
      <div className="mx-auto max-w-7xl px-6 lg:px-8">
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="text-4xl font-bold tracking-tight text-gray-900 sm:text-5xl">
            Simple, Transparent Pricing
          </h2>
          <p className="mt-4 text-lg leading-8 text-gray-600">
            Start free. Upgrade when you&apos;re ready.
          </p>
        </div>

        {/* Cards grid */}
        <div className="mx-auto mt-16 grid max-w-5xl grid-cols-1 gap-8 lg:grid-cols-2">
          {/* ----------------------------------------------------------------
              Free Plan Card
          ---------------------------------------------------------------- */}
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
            className="glass relative flex flex-col rounded-2xl p-8 sm:p-10"
          >
            <h3 className="text-2xl font-semibold text-gray-900">Free</h3>

            {/* Price */}
            <div className="mt-6 flex items-baseline gap-x-1">
              <span className="text-5xl font-bold tracking-tight text-gray-900">
                $0
              </span>
              <span className="text-base font-medium text-gray-500">
                /forever
              </span>
            </div>

            {/* Features */}
            <ul className="mt-8 flex flex-col gap-y-4 text-sm leading-6 text-gray-700">
              {FREE_FEATURES.map((feature) => (
                <li key={feature} className="flex items-start gap-x-3">
                  <CheckIcon className="h-5 w-5 flex-shrink-0 text-brand-500" />
                  <span>{feature}</span>
                </li>
              ))}
            </ul>

            {/* CTA */}
            <div className="mt-auto pt-10">
              <a
                href="#download"
                className="block w-full rounded-xl border-2 border-brand-500 px-6 py-3.5 text-center text-sm font-semibold text-brand-600 transition-colors duration-200 hover:bg-brand-50 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-500"
              >
                Get Started
              </a>
            </div>
          </motion.div>

          {/* ----------------------------------------------------------------
              Pro Plan Card (featured)
          ---------------------------------------------------------------- */}
          <motion.div
            custom={1}
            variants={cardVariants}
            initial="hidden"
            whileInView="visible"
            viewport={{ once: true, margin: "-80px" }}
            whileHover={{
              y: -6,
              boxShadow:
                "0 20px 60px -12px rgba(249, 115, 22, 0.25), 0 8px 24px -8px rgba(249, 115, 22, 0.15)",
            }}
            transition={{ type: "spring", stiffness: 260, damping: 20 }}
            className="relative flex flex-col rounded-2xl p-8 sm:p-10"
            style={{
              // Double-layered glass + brand gradient border via
              // background-origin trick (outer = gradient, inner = glass fill)
              background:
                "linear-gradient(rgba(255,255,255,0.85), rgba(255,255,255,0.85)) padding-box, linear-gradient(135deg, #F97316, #FB923C, #FBBF24) border-box",
              border: "2px solid transparent",
              backdropFilter: "blur(20px) saturate(180%)",
              WebkitBackdropFilter: "blur(20px) saturate(180%)",
              boxShadow:
                "0 0 40px rgba(249, 115, 22, 0.12), 0 0 80px rgba(249, 115, 22, 0.06)",
            }}
          >
            {/* "Most Popular" badge */}
            <div className="absolute -top-4 left-1/2 -translate-x-1/2">
              <span className="inline-flex items-center rounded-full bg-gradient-to-r from-brand-500 to-brand-600 px-4 py-1.5 text-xs font-bold uppercase tracking-wider text-white shadow-lg shadow-brand-500/30">
                Most Popular
              </span>
            </div>

            <h3 className="text-2xl font-semibold text-gray-900">Pro</h3>

            {/* Price */}
            <div className="mt-6 flex items-baseline gap-x-1">
              <span className="text-5xl font-bold tracking-tight text-gray-900">
                $19.99
              </span>
              <span className="text-base font-medium text-gray-500">
                /month
              </span>
            </div>
            <p className="mt-2 text-sm text-gray-500">
              $199.99/year — Save 17%
            </p>

            {/* Features */}
            <ul className="mt-8 flex flex-col gap-y-4 text-sm leading-6 text-gray-700">
              {PRO_FEATURES.map((feature) => (
                <li key={feature} className="flex items-start gap-x-3">
                  <CheckIcon className="h-5 w-5 flex-shrink-0 text-brand-500" />
                  <span>{feature}</span>
                </li>
              ))}
            </ul>

            {/* CTA */}
            <div className="mt-auto pt-10">
              <a
                href="#download"
                className="block w-full rounded-xl bg-brand-500 px-6 py-3.5 text-center text-sm font-semibold text-white shadow-lg shadow-brand-500/30 transition-all duration-200 hover:bg-brand-600 hover:shadow-brand-600/40 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-500"
              >
                Start 7-Day Free Trial
              </a>
            </div>
          </motion.div>
        </div>
      </div>
    </section>
  );
}
