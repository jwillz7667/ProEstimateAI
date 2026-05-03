import Navbar from "@/components/Navbar";
import Hero from "@/components/Hero";
import Features from "@/components/Features";
import HowItWorks from "@/components/HowItWorks";
import EstimateShowcase from "@/components/EstimateShowcase";
import AppShowcase from "@/components/AppShowcase";
import Pricing from "@/components/Pricing";
import CTA from "@/components/CTA";
import Footer from "@/components/Footer";

export default function Home() {
  return (
    <>
      <Navbar />
      <main id="main">
        <Hero />
        <Features />
        <HowItWorks />
        <EstimateShowcase />
        <AppShowcase />
        <Pricing />
        <CTA />
      </main>
      <Footer />
    </>
  );
}
