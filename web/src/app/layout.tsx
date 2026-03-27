import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import "./globals.css";

const inter = Inter({
  subsets: ["latin"],
  display: "swap",
  variable: "--font-inter",
});

const SITE_URL = "https://proestimateai.com";
const SITE_NAME = "ProEstimate AI";
const SITE_DESCRIPTION =
  "Transform renovation projects with AI. Upload photos, get realistic remodel previews, instant material lists with supplier links, and professional cost estimates — in minutes, not days.";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: "ProEstimate AI — AI-Powered Remodel Previews & Cost Estimates",
    template: "%s | ProEstimate AI",
  },
  description: SITE_DESCRIPTION,
  keywords: [
    "AI remodel preview",
    "renovation estimate",
    "home remodel cost",
    "contractor estimate software",
    "AI construction estimate",
    "kitchen remodel cost",
    "bathroom renovation estimate",
    "material cost calculator",
    "DIY project estimate",
    "contractor invoicing",
    "remodel before and after",
    "AI home design",
    "ProEstimate",
  ],
  authors: [{ name: "ProEstimate AI" }],
  creator: "ProEstimate AI",
  publisher: "ProEstimate AI",
  formatDetection: {
    email: false,
    address: false,
    telephone: false,
  },
  openGraph: {
    type: "website",
    locale: "en_US",
    url: SITE_URL,
    siteName: SITE_NAME,
    title: "ProEstimate AI — See Your Remodel Before You Build",
    description: SITE_DESCRIPTION,
    images: [
      {
        url: "/og-image.png",
        width: 1200,
        height: 630,
        alt: "ProEstimate AI — AI-Powered Remodel Previews",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "ProEstimate AI — AI-Powered Remodel Previews & Cost Estimates",
    description: SITE_DESCRIPTION,
    images: ["/og-image.png"],
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-video-preview": -1,
      "max-image-preview": "large",
      "max-snippet": -1,
    },
  },
  alternates: {
    canonical: SITE_URL,
  },
  icons: {
    icon: "/favicon.ico",
    apple: "/apple-touch-icon.png",
  },
  manifest: "/manifest.json",
};

export const viewport: Viewport = {
  themeColor: "#F97316",
  width: "device-width",
  initialScale: 1,
  maximumScale: 5,
};

const jsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: SITE_NAME,
  applicationCategory: "BusinessApplication",
  operatingSystem: "iOS",
  description: SITE_DESCRIPTION,
  url: SITE_URL,
  offers: {
    "@type": "Offer",
    price: "0",
    priceCurrency: "USD",
    description: "Free with 3 AI previews. Pro plans available.",
  },
  aggregateRating: {
    "@type": "AggregateRating",
    ratingValue: "4.9",
    ratingCount: "127",
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className={inter.variable}>
      <head>
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
        />
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link
          rel="preconnect"
          href="https://fonts.gstatic.com"
          crossOrigin="anonymous"
        />
      </head>
      <body className="min-h-screen bg-surface font-sans antialiased">
        {children}
      </body>
    </html>
  );
}
