import type { MetadataRoute } from "next";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: "/",
        // /proposal/:token pages are per-client share links — the page also
        // sets <meta name="robots" content="noindex,nofollow">, but list it
        // here as a belt-and-suspenders safeguard against accidental indexing.
        disallow: ["/api/", "/proposal/"],
      },
    ],
    sitemap: "https://proestimateai.com/sitemap.xml",
  };
}
