import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import { APP_STORE_URL } from "@/lib/constants";
import "./globals.css";

const inter = Inter({
  subsets: ["latin"],
  display: "swap",
  variable: "--font-inter",
});

const SITE_URL = "https://proestimateai.com";
const SITE_NAME = "ProEstimate AI";
const SITE_DESCRIPTION =
  "AI-powered remodel previews, itemized material lists, and contractor-grade cost estimates for iOS. Snap a photo, see the finished room, send a branded proposal — in under a minute.";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default:
      "ProEstimate AI — AI Remodel Previews & Contractor Estimates for iOS",
    template: "%s | ProEstimate AI",
  },
  description: SITE_DESCRIPTION,
  applicationName: SITE_NAME,
  category: "business",
  keywords: [
    "AI remodel preview",
    "AI renovation app",
    "contractor estimate software",
    "construction estimating app",
    "AI material list",
    "kitchen remodel cost calculator",
    "bathroom renovation estimate",
    "roofing estimate app",
    "siding cost estimator",
    "painting estimate software",
    "landscaping estimate app",
    "iOS contractor app",
    "AI before and after renovation",
    "branded proposal generator",
    "construction invoice app",
    "ProEstimate",
    "ProEstimate AI",
  ],
  authors: [{ name: "Viral Ventures LLC", url: SITE_URL }],
  creator: "Viral Ventures LLC",
  publisher: "Viral Ventures LLC",
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
    title: "ProEstimate AI — See the Remodel Before You Build It",
    description: SITE_DESCRIPTION,
    images: [
      {
        url: "/og-image.png",
        width: 1200,
        height: 630,
        alt: "ProEstimate AI — AI-Powered Remodel Previews and Contractor Estimates",
        type: "image/png",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title:
      "ProEstimate AI — AI Remodel Previews & Contractor Estimates for iOS",
    description: SITE_DESCRIPTION,
    images: [
      {
        url: "/og-image.png",
        alt: "ProEstimate AI — AI-Powered Remodel Previews and Contractor Estimates",
      },
    ],
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
    languages: { "en-US": SITE_URL, "x-default": SITE_URL },
  },
  icons: {
    icon: [
      { url: "/favicon.ico", sizes: "any" },
      { url: "/favicon-16.png", sizes: "16x16", type: "image/png" },
      { url: "/favicon-32.png", sizes: "32x32", type: "image/png" },
      { url: "/icon-192.png", sizes: "192x192", type: "image/png" },
      { url: "/icon-512.png", sizes: "512x512", type: "image/png" },
    ],
    apple: [{ url: "/apple-touch-icon.png", sizes: "180x180" }],
    shortcut: "/favicon.ico",
  },
  manifest: "/manifest.json",
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: SITE_NAME,
  },
  itunes: {
    appId: "6762563132",
    appArgument: SITE_URL,
  },
  other: {
    "apple-mobile-web-app-title": SITE_NAME,
    "format-detection": "telephone=no",
  },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#FF9230" },
    { media: "(prefers-color-scheme: dark)", color: "#1C1C1E" },
  ],
  width: "device-width",
  initialScale: 1,
  maximumScale: 5,
  colorScheme: "light dark",
};

const organizationLd = {
  "@context": "https://schema.org",
  "@type": "Organization",
  "@id": `${SITE_URL}#organization`,
  name: "Viral Ventures LLC",
  alternateName: "ProEstimate AI",
  url: SITE_URL,
  logo: {
    "@type": "ImageObject",
    url: `${SITE_URL}/icon-512.png`,
    width: 512,
    height: 512,
  },
  foundingLocation: {
    "@type": "Place",
    address: {
      "@type": "PostalAddress",
      addressRegion: "MN",
      addressCountry: "US",
    },
  },
  email: "support@proestimateai.com",
  contactPoint: [
    {
      "@type": "ContactPoint",
      email: "support@proestimateai.com",
      contactType: "customer support",
      availableLanguage: ["English", "Spanish"],
      areaServed: "US",
    },
    {
      "@type": "ContactPoint",
      email: "privacy@proestimateai.com",
      contactType: "privacy",
      availableLanguage: ["English"],
    },
  ],
};

const websiteLd = {
  "@context": "https://schema.org",
  "@type": "WebSite",
  "@id": `${SITE_URL}#website`,
  url: SITE_URL,
  name: SITE_NAME,
  description: SITE_DESCRIPTION,
  inLanguage: "en-US",
  publisher: { "@id": `${SITE_URL}#organization` },
};

const mobileAppLd = {
  "@context": "https://schema.org",
  "@type": "MobileApplication",
  "@id": `${SITE_URL}#app`,
  name: SITE_NAME,
  alternateName: "ProEstimate",
  description: SITE_DESCRIPTION,
  applicationCategory: "BusinessApplication",
  applicationSubCategory: "Construction Estimating",
  operatingSystem: "iOS 26.4",
  url: SITE_URL,
  downloadUrl: APP_STORE_URL,
  installUrl: APP_STORE_URL,
  image: `${SITE_URL}/og-image.png`,
  screenshot: [
    `${SITE_URL}/screenshots/dashboard.jpg`,
    `${SITE_URL}/screenshots/ai-preview.jpg`,
    `${SITE_URL}/screenshots/estimate-ready.jpg`,
    `${SITE_URL}/screenshots/materials.jpg`,
  ],
  inLanguage: ["en-US", "es-US"],
  publisher: { "@id": `${SITE_URL}#organization` },
  author: { "@id": `${SITE_URL}#organization` },
  offers: [
    {
      "@type": "Offer",
      name: "Free",
      price: "0",
      priceCurrency: "USD",
      description:
        "Five lifetime AI preview generations and three estimate exports. No credit card required.",
    },
    {
      "@type": "Offer",
      name: "Pro Monthly",
      price: "19.99",
      priceCurrency: "USD",
      priceSpecification: {
        "@type": "UnitPriceSpecification",
        price: "19.99",
        priceCurrency: "USD",
        billingDuration: "P1M",
      },
      description:
        "20 AI previews and 50 quote exports per month, branded PDFs, invoices, and client approval links.",
    },
    {
      "@type": "Offer",
      name: "Pro Annual",
      price: "149.99",
      priceCurrency: "USD",
      priceSpecification: {
        "@type": "UnitPriceSpecification",
        price: "149.99",
        priceCurrency: "USD",
        billingDuration: "P1Y",
      },
      description: "Pro plan billed annually — saves 37% vs monthly.",
    },
    {
      "@type": "Offer",
      name: "Premium Monthly",
      price: "49.99",
      priceCurrency: "USD",
      priceSpecification: {
        "@type": "UnitPriceSpecification",
        price: "49.99",
        priceCurrency: "USD",
        billingDuration: "P1M",
      },
      description:
        "Unlimited projects, priority generation queue, and up to 200 AI previews per day.",
    },
  ],
  featureList: [
    "AI-generated photoreal remodel previews",
    "Itemized material lists with supplier links",
    "Contractor-grade cost estimates",
    "Branded proposals and invoices",
    "Client approval share links",
    "14 project types — kitchen, bath, roofing, siding, painting, flooring, exterior, landscaping, and more",
    "Apple Liquid Glass interface, Dark Mode, and Spanish localization",
  ],
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className={inter.variable}>
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link
          rel="preconnect"
          href="https://fonts.gstatic.com"
          crossOrigin="anonymous"
        />
        <link rel="dns-prefetch" href="https://apps.apple.com" />
        <meta name="apple-itunes-app" content="app-id=6762563132" />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(organizationLd) }}
        />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(websiteLd) }}
        />
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{ __html: JSON.stringify(mobileAppLd) }}
        />
      </head>
      <body className="min-h-screen bg-surface font-sans antialiased">
        {children}
      </body>
    </html>
  );
}
