import type { MetadataRoute } from "next";

const SITE_URL = "https://proestimateai.com";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: "/",
        // /proposal/:token pages are per-client share links — the page also
        // sets <meta name="robots" content="noindex,nofollow">, but list it
        // here as a belt-and-suspenders safeguard against accidental indexing.
        // /api/* serves backend JSON proxies; /_next/* is the Next.js build asset
        // tree which Google can crawl but doesn't need to index.
        disallow: ["/api/", "/proposal/", "/reset-password", "/_next/static/chunks/"],
      },
      {
        userAgent: "GPTBot",
        disallow: ["/proposal/", "/reset-password"],
      },
      {
        userAgent: "ClaudeBot",
        disallow: ["/proposal/", "/reset-password"],
      },
      {
        userAgent: "CCBot",
        disallow: ["/proposal/", "/reset-password"],
      },
    ],
    sitemap: `${SITE_URL}/sitemap.xml`,
    host: SITE_URL,
  };
}
