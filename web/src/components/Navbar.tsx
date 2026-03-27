"use client";

import { useState, useEffect, useCallback } from "react";
import { motion, AnimatePresence, useMotionValueEvent, useScroll } from "framer-motion";
import clsx from "clsx";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface NavLink {
  label: string;
  href: string;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const NAV_LINKS: NavLink[] = [
  { label: "Features", href: "#features" },
  { label: "How It Works", href: "#how-it-works" },
  { label: "Pricing", href: "#pricing" },
];

const APP_STORE_URL = "https://apps.apple.com/app/proestimate-ai/id0000000000";

const SCROLL_THRESHOLD = 32;

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

/** Animated hamburger icon that morphs into an X when the drawer is open. */
function HamburgerIcon({ isOpen }: { isOpen: boolean }) {
  const lineCommon = "block h-[2px] w-5 rounded-full bg-ink-950 transition-all duration-300 origin-center";
  return (
    <div className="flex flex-col items-center justify-center gap-[5px]">
      <span
        className={clsx(lineCommon, isOpen && "translate-y-[7px] rotate-45")}
      />
      <span
        className={clsx(lineCommon, isOpen && "opacity-0 scale-x-0")}
      />
      <span
        className={clsx(lineCommon, isOpen && "-translate-y-[7px] -rotate-45")}
      />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Navbar
// ---------------------------------------------------------------------------

export default function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const { scrollY } = useScroll();

  // Track scroll position to toggle glass background
  useMotionValueEvent(scrollY, "change", (latest) => {
    setScrolled(latest > SCROLL_THRESHOLD);
  });

  // Lock body scroll when mobile drawer is open
  useEffect(() => {
    if (drawerOpen) {
      document.body.style.overflow = "hidden";
    } else {
      document.body.style.overflow = "";
    }
    return () => {
      document.body.style.overflow = "";
    };
  }, [drawerOpen]);

  // Close drawer on Escape key
  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === "Escape") setDrawerOpen(false);
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  const handleNavClick = useCallback(() => {
    setDrawerOpen(false);
  }, []);

  return (
    <>
      {/* ----------------------------------------------------------------- */}
      {/* Sticky header bar                                                   */}
      {/* ----------------------------------------------------------------- */}
      <motion.header
        initial={{ y: -100 }}
        animate={{ y: 0 }}
        transition={{ type: "spring", stiffness: 260, damping: 28 }}
        className={clsx(
          "fixed inset-x-0 top-0 z-50 transition-colors duration-300",
          scrolled
            ? "border-b border-white/30 bg-white/70 shadow-sm backdrop-blur-[20px] backdrop-saturate-[180%] [-webkit-backdrop-filter:blur(20px)_saturate(180%)]"
            : "bg-transparent",
        )}
      >
        <nav className="mx-auto flex h-16 max-w-7xl items-center justify-between px-5 sm:px-8">
          {/* Logo */}
          <a
            href="#"
            aria-label="ProEstimate AI home"
            className="flex items-baseline gap-0.5 text-xl tracking-tight select-none"
            onClick={handleNavClick}
          >
            <span className="font-bold text-ink-950">ProEstimate</span>
            <span className="font-bold text-brand-500">AI</span>
          </a>

          {/* Desktop nav links */}
          <ul className="hidden items-center gap-8 md:flex">
            {NAV_LINKS.map((link) => (
              <li key={link.href}>
                <a
                  href={link.href}
                  className="relative text-sm font-medium text-ink-500 transition-colors duration-200 hover:text-ink-950"
                >
                  {link.label}
                  {/* Animated underline on hover */}
                  <span className="absolute -bottom-1 left-0 h-[2px] w-0 rounded-full bg-brand-500 transition-all duration-300 group-hover:w-full" />
                </a>
              </li>
            ))}
          </ul>

          {/* Desktop CTA */}
          <div className="hidden md:block">
            <motion.a
              href={APP_STORE_URL}
              target="_blank"
              rel="noopener noreferrer"
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.97 }}
              className="inline-flex items-center gap-2 rounded-full bg-brand-500 px-5 py-2.5 text-sm font-semibold text-white shadow-md shadow-brand-500/25 transition-colors duration-200 hover:bg-brand-600"
            >
              {/* Apple icon (inline SVG to avoid extra dependency) */}
              <svg
                className="h-4 w-4 fill-current"
                viewBox="0 0 384 512"
                aria-hidden="true"
              >
                <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-27.1-46.9-42.2-83.7-45.3-35.1-3-73.5 20.7-87.6 20.7-14.8 0-49-19.7-74.4-19.7C63.1 141.2 0 184.8 0 273.5c0 26.2 4.8 53.3 14.4 81.2 12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-62.1 24-72.5-24 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z" />
              </svg>
              Download App
            </motion.a>
          </div>

          {/* Mobile hamburger button */}
          <button
            type="button"
            onClick={() => setDrawerOpen((prev) => !prev)}
            className="relative z-50 flex h-10 w-10 items-center justify-center rounded-lg transition-colors duration-200 hover:bg-ink-100 md:hidden"
            aria-label={drawerOpen ? "Close navigation menu" : "Open navigation menu"}
            aria-expanded={drawerOpen}
          >
            <HamburgerIcon isOpen={drawerOpen} />
          </button>
        </nav>
      </motion.header>

      {/* ----------------------------------------------------------------- */}
      {/* Mobile drawer overlay + panel                                       */}
      {/* ----------------------------------------------------------------- */}
      <AnimatePresence>
        {drawerOpen && (
          <>
            {/* Backdrop */}
            <motion.div
              key="backdrop"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.25 }}
              className="fixed inset-0 z-40 bg-black/30 backdrop-blur-sm md:hidden"
              onClick={() => setDrawerOpen(false)}
              aria-hidden="true"
            />

            {/* Drawer panel */}
            <motion.div
              key="drawer"
              initial={{ x: "100%" }}
              animate={{ x: 0 }}
              exit={{ x: "100%" }}
              transition={{ type: "spring", stiffness: 320, damping: 34 }}
              className="fixed right-0 top-0 z-40 flex h-full w-72 flex-col border-l border-white/30 bg-white/80 shadow-2xl backdrop-blur-[20px] backdrop-saturate-[180%] [-webkit-backdrop-filter:blur(20px)_saturate(180%)] md:hidden"
            >
              {/* Top spacing to clear the header */}
              <div className="h-20 shrink-0" />

              {/* Links */}
              <nav className="flex flex-col gap-1 px-6">
                {NAV_LINKS.map((link, i) => (
                  <motion.a
                    key={link.href}
                    href={link.href}
                    onClick={handleNavClick}
                    initial={{ opacity: 0, x: 24 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ delay: 0.08 * i, duration: 0.3 }}
                    className="rounded-lg px-4 py-3 text-base font-medium text-ink-700 transition-colors duration-200 hover:bg-brand-50 hover:text-brand-600"
                  >
                    {link.label}
                  </motion.a>
                ))}
              </nav>

              {/* Mobile CTA */}
              <div className="mt-auto px-6 pb-10">
                <motion.a
                  href={APP_STORE_URL}
                  target="_blank"
                  rel="noopener noreferrer"
                  onClick={handleNavClick}
                  initial={{ opacity: 0, y: 16 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: 0.25, duration: 0.35 }}
                  whileTap={{ scale: 0.97 }}
                  className="flex w-full items-center justify-center gap-2 rounded-full bg-brand-500 px-6 py-3 text-base font-semibold text-white shadow-lg shadow-brand-500/25 transition-colors duration-200 hover:bg-brand-600"
                >
                  <svg
                    className="h-4 w-4 fill-current"
                    viewBox="0 0 384 512"
                    aria-hidden="true"
                  >
                    <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-27.1-46.9-42.2-83.7-45.3-35.1-3-73.5 20.7-87.6 20.7-14.8 0-49-19.7-74.4-19.7C63.1 141.2 0 184.8 0 273.5c0 26.2 4.8 53.3 14.4 81.2 12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-62.1 24-72.5-24 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z" />
                  </svg>
                  Download App
                </motion.a>
              </div>
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </>
  );
}
