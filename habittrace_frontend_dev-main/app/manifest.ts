import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    id: "/dashboard/today",
    name: "HabitTrace - Plan and Follow Through",
    short_name: "HabitTrace",
    description: "Quickly add plans, start them, and record the outcome.",
    lang: "en",
    start_url: "/dashboard/today",
    scope: "/",
    display: "standalone",
    orientation: "natural",
    background_color: "#f8fafc",
    theme_color: "#0f172a",
    categories: ["productivity", "lifestyle"],
    icons: [
      {
        src: "/icons/habittrace-192.png",
        sizes: "192x192",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/icons/habittrace-512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/icons/habittrace-maskable-512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "maskable",
      },
    ],
    shortcuts: [
      {
        name: "Quick Add a plan",
        short_name: "Quick Add",
        description: "Add a new plan to HabitTrace.",
        url: "/dashboard/today#quick-add",
        icons: [
          {
            src: "/icons/habittrace-192.png",
            sizes: "192x192",
            type: "image/png",
          },
        ],
      },
    ],
  };
}
