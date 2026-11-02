import { ImageResponse } from "next/og";

// App icon: three score bars in the three course colours.
export function generateImageMetadata() {
  return [192, 512].map((n) => ({ id: String(n), size: { width: n, height: n }, contentType: "image/png" }));
}

export function Mark({ size }: { size: number }) {
  const u = size / 16;
  return (
    <div style={{ width: size, height: size, display: "flex", alignItems: "flex-end", justifyContent: "center", gap: u, padding: 3.5 * u, background: "#fcfcfb" }}>
      {[["#2d6fbe", 7], ["#17843f", 9], ["#aa5300", 6]].map(([c, h]) => (
        <div key={c} style={{ width: 2.5 * u, height: (h as number) * u, background: c as string, borderRadius: `${0.6 * u}px ${0.6 * u}px 0 0` }} />
      ))}
    </div>
  );
}

export default async function Icon({ id }: { id: Promise<string> }) {
  const size = Number(await id);
  return new ImageResponse(<Mark size={size} />, { width: size, height: size });
}
