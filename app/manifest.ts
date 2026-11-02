import type { MetadataRoute } from "next";

// Makes the site installable ("Add to Home Screen") so it opens like an app.
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Academic Assistant",
    short_name: "Academics",
    start_url: "/",
    display: "standalone",
    background_color: "#fcfcfb",
    theme_color: "#fcfcfb",
    icons: [
      { src: "/icon/192", sizes: "192x192", type: "image/png" },
      { src: "/icon/512", sizes: "512x512", type: "image/png" },
    ],
  };
}
