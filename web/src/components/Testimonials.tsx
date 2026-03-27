"use client";

import { Swiper, SwiperSlide } from "swiper/react";
import { Autoplay, Pagination } from "swiper/modules";

import "swiper/css";
import "swiper/css/pagination";

// ---------------------------------------------------------------------------
// Testimonial data
// ---------------------------------------------------------------------------

interface Testimonial {
  quote: string;
  author: string;
  role: string;
}

const testimonials: Testimonial[] = [
  {
    quote:
      "ProEstimate AI cut my quoting time from 3 hours to 15 minutes. My clients love the AI previews.",
    author: "Mike Chen",
    role: "General Contractor",
  },
  {
    quote:
      "I used this to plan my kitchen remodel as a DIY project. Knowing the exact materials and costs saved me thousands.",
    author: "Sarah Mitchell",
    role: "Homeowner",
  },
  {
    quote:
      "The material lists with supplier links are incredible. No more guessing quantities or hunting for prices.",
    author: "Carlos Rivera",
    role: "Renovation Specialist",
  },
  {
    quote:
      "I show clients the AI preview and they sign on the spot. It's changed how I close deals.",
    author: "James Thompson",
    role: "Kitchen & Bath Pro",
  },
  {
    quote:
      "Finally an estimate tool that understands both DIY and professional pricing. Game changer for our business.",
    author: "Lisa Park",
    role: "Interior Designer",
  },
];

// ---------------------------------------------------------------------------
// Star rating component (5 filled orange stars)
// ---------------------------------------------------------------------------

function StarRating() {
  return (
    <div className="flex gap-x-1" aria-label="5 out of 5 stars">
      {Array.from({ length: 5 }).map((_, i) => (
        <svg
          key={i}
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 20 20"
          fill="currentColor"
          aria-hidden="true"
          className="h-5 w-5 text-brand-500"
        >
          <path
            fillRule="evenodd"
            d="M10.868 2.884c-.321-.772-1.415-.772-1.736 0l-1.83 4.401-4.753.381c-.833.067-1.171 1.107-.536 1.651l3.62 3.102-1.106 4.637c-.194.813.691 1.456 1.405 1.02L10 15.591l4.069 2.485c.713.436 1.598-.207 1.404-1.02l-1.106-4.637 3.62-3.102c.635-.544.297-1.584-.536-1.65l-4.752-.382-1.831-4.401Z"
            clipRule="evenodd"
          />
        </svg>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Testimonials Section
// ---------------------------------------------------------------------------

export default function Testimonials() {
  return (
    <section
      id="testimonials"
      className="relative overflow-hidden py-24 sm:py-32"
    >
      <div className="mx-auto max-w-7xl px-6 lg:px-8">
        {/* Section header */}
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="text-4xl font-bold tracking-tight text-gray-900 sm:text-5xl">
            Loved by Contractors &amp; Homeowners
          </h2>
        </div>

        {/* Swiper carousel */}
        <div className="mt-16">
          <Swiper
            modules={[Autoplay, Pagination]}
            spaceBetween={24}
            slidesPerView={1}
            centeredSlides
            loop
            autoplay={{
              delay: 4500,
              disableOnInteraction: false,
              pauseOnMouseEnter: true,
            }}
            pagination={{
              clickable: true,
              dynamicBullets: true,
            }}
            breakpoints={{
              // Tablet: 2 slides
              768: {
                slidesPerView: 2,
                spaceBetween: 28,
              },
              // Desktop: 3 slides
              1024: {
                slidesPerView: 3,
                spaceBetween: 32,
              },
            }}
            className="pb-14"
          >
            {testimonials.map((t) => (
              <SwiperSlide key={t.author}>
                <div className="glass group flex h-full flex-col rounded-2xl p-8 transition-shadow duration-300 hover:shadow-xl hover:shadow-brand-500/10">
                  {/* Star rating */}
                  <StarRating />

                  {/* Quote */}
                  <blockquote className="mt-5 flex-1 text-base italic leading-7 text-gray-700">
                    &ldquo;{t.quote}&rdquo;
                  </blockquote>

                  {/* Author */}
                  <div className="mt-6 border-t border-gray-200/60 pt-5">
                    <p className="text-sm font-semibold text-gray-900">
                      {t.author}
                    </p>
                    <p className="mt-0.5 text-sm text-gray-500">{t.role}</p>
                  </div>
                </div>
              </SwiperSlide>
            ))}
          </Swiper>
        </div>
      </div>
    </section>
  );
}
