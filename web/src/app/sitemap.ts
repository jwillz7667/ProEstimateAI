import type { MetadataRoute } from "next";

const SITE_URL = "https://proestimateai.com";

export default function sitemap(): MetadataRoute.Sitemap {
  const lastBuild = new Date();

  return [
    {
      url: SITE_URL,
      lastModified: lastBuild,
      changeFrequency: "weekly",
      priority: 1,
    },
    {
      url: `${SITE_URL}/support`,
      lastModified: lastBuild,
      changeFrequency: "weekly",
      priority: 0.7,
    },
    {
      url: `${SITE_URL}/privacy`,
      lastModified: new Date("2026-03-26"),
      changeFrequency: "yearly",
      priority: 0.3,
    },
    {
      url: `${SITE_URL}/terms`,
      lastModified: new Date("2026-03-26"),
      changeFrequency: "yearly",
      priority: 0.3,
    },
  ];
}
