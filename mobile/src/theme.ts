import { useColorScheme } from "react-native";
import type { Hue } from "./data";

// Same tokens as the website's app/(dashboard)/dashboard.css. Shade ramps were validated with the
// dataviz palette validator (ordinal, light + dark); index = weight band 0..3 (<5, 5–15, 15–30, >30%).
// Dark mode flips the ramp so heavier weight = brighter (more prominent on the dark surface).
const light = {
  dark: false,
  surface: "#fcfcfb",
  card: "#ffffff",
  ink: "#1a1a1c",
  ink2: "#55555b",
  ink3: "#75757b",
  hairline: "#e6e6e2",
  backdrop: "rgba(0,0,0,0.45)",
  hues: {
    blue: { shades: ["#85b4f0", "#5591dd", "#2d6fbe", "#154d8c"], tint: "#e9f3ff" },
    green: { shades: ["#82c38f", "#4ca563", "#17843f", "#005e26"], tint: "#e7f7e9" },
    orange: { shades: ["#e3a072", "#cb7738", "#aa5300", "#7c3600"], tint: "#ffeee2" },
  },
};

const dark: typeof light = {
  dark: true,
  surface: "#141416",
  card: "#1d1d20",
  ink: "#ececee",
  ink2: "#a9a9b0",
  ink3: "#8c8c93",
  hairline: "#2e2e33",
  backdrop: "rgba(0,0,0,0.6)",
  hues: {
    blue: { shades: ["#2d4e78", "#3d73b6", "#5b9df0", "#9eceff"], tint: "#142234" },
    green: { shades: ["#295935", "#33854a", "#51b36b", "#9bdda8"], tint: "#132717" },
    orange: { shades: ["#6e401e", "#a65c20", "#dc813b", "#feb98b"], tint: "#301c0e" },
  },
};

export type Theme = typeof light;

export const useTheme = (): Theme => (useColorScheme() === "dark" ? dark : light);

/** A subject's colours: shades[band], accent (main colour, for marks only — never text), tint (card wash). */
export const hueOf = (t: Theme, h: Hue) => ({ ...t.hues[h], accent: t.hues[h].shades[2] });

/** Centred column so the layout stays phone-shaped on a laptop window. */
export const page = { width: "100%", maxWidth: 560, alignSelf: "center", paddingHorizontal: 16 } as const;
