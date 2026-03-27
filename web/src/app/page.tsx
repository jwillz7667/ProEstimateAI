import Navbar from "@/components/Navbar";
import Hero from "@/components/Hero";
import Features from "@/components/Features";
import HowItWorks from "@/components/HowItWorks";
import AppShowcase from "@/components/AppShowcase";
import Pricing from "@/components/Pricing";
import Testimonials from "@/components/Testimonials";
import CTA from "@/components/CTA";
import Footer from "@/components/Footer";


export default function Home() {
  return (
    <>
      <Navbar />

      {/* Hero */}
      <section className="relative overflow-hidden bg-white">
        <Hero />
      </section>

      {/* Features */}
      <Features />

      {/* How It Works */}
      <HowItWorks />

      {/* App Showcase Carousel */}
      <AppShowcase />

      {/* Testimonials */}
      <Testimonials />

      {/* Pricing */}
      <Pricing />

      {/* Final CTA */}
      <CTA />

      {/* Footer */}
      <Footer />
    </>
  );
}
