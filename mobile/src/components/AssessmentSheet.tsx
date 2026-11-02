import { useState } from "react";
import { Modal, Platform, Pressable, StyleSheet, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { band, bandLabels, type Assessment, type Hue } from "@/data";
import { hueOf, useTheme } from "@/theme";

export const fmtDate = (iso: string) =>
  new Date(iso).toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short", year: "numeric" }).replace(/,/g, "");

const ios = Platform.OS === "ios";

export function AssessmentSheet({ assessment, hue, onClose }: { assessment: Assessment | null; hue: Hue; onClose: () => void }) {
  const t = useTheme();
  const { shades, tint } = hueOf(t, hue);
  const insets = useSafeAreaInsets();
  // Keep the last assessment so the sheet still has content while it animates closed.
  const [a, setA] = useState(assessment);
  if (assessment && assessment !== a) setA(assessment);

  const up = a?.score === undefined;
  const body = a && (
    <>
      <View style={s.head}>
        <Text style={[s.title, { color: t.ink }]} accessibilityRole="header">{a.name}</Text>
        <Pressable
          onPress={onClose}
          accessibilityRole="button"
          accessibilityLabel="Close"
          style={({ pressed }) => [s.close, { borderColor: t.hairline }, pressed && { backgroundColor: t.hairline }]}
        >
          <Text style={{ color: t.ink, fontSize: 15 }}>Close</Text>
        </Pressable>
      </View>
      {up && <Text style={[s.status, { color: t.ink2 }]}>Upcoming, not graded yet</Text>}
      <View style={s.facts}>
        {([
          ["Type", a.type],
          ["Date", fmtDate(a.date)],
          ["Raw score", a.raw ? `${a.raw.got} / ${a.raw.max}` : "—"],
          ["Score", up ? "—" : `${a.score}%`],
        ] as const).map(([k, v]) => (
          <View key={k} style={s.row}>
            <Text style={[s.key, { color: t.ink3 }]}>{k}</Text>
            <Text style={[s.val, { color: t.ink }]}>{v}</Text>
          </View>
        ))}
        <View style={s.row}>
          <Text style={[s.key, { color: t.ink3 }]}>Weight</Text>
          <View style={[s.val, s.weight]}>
            <View style={[s.swatch, { backgroundColor: shades[band(a.weight)] }]} />
            <Text style={{ color: t.ink, fontSize: 15, flexShrink: 1 }}>
              {a.weight}% of course grade <Text style={{ color: t.ink3 }}>({bandLabels[band(a.weight)]} band)</Text>
            </Text>
          </View>
        </View>
      </View>
      <Text style={[s.topicsTitle, { color: t.ink2 }]}>Topics covered</Text>
      <View style={s.chips}>
        {a.topics.map((topic) => (
          <Text key={topic} style={[s.chip, { backgroundColor: tint, color: t.ink }]}>{topic}</Text>
        ))}
      </View>
    </>
  );

  // iOS: native card sheet, swipe-down calls onRequestClose. Web/Android: dimmed backdrop + bottom card.
  // react-native-web's Modal calls onRequestClose on Escape.
  if (ios)
    return (
      <Modal visible={!!assessment} presentationStyle="pageSheet" animationType="slide" onRequestClose={onClose}>
        <View style={[s.iosCard, { backgroundColor: t.card }]}>{body}</View>
      </Modal>
    );

  return (
    <Modal visible={!!assessment} transparent animationType="fade" onRequestClose={onClose}>
      <View style={s.fill}>
        <Pressable
          style={[StyleSheet.absoluteFill, { backgroundColor: t.backdrop }]}
          onPress={onClose}
          accessibilityRole="button"
          accessibilityLabel="Close"
        />
        <View style={[s.card, { backgroundColor: t.card, paddingBottom: 20 + insets.bottom }]} accessibilityViewIsModal>
          {body}
        </View>
      </View>
    </Modal>
  );
}

const s = StyleSheet.create({
  fill: { flex: 1, justifyContent: "flex-end" },
  card: { width: "100%", maxWidth: 560, alignSelf: "center", borderTopLeftRadius: 16, borderTopRightRadius: 16, padding: 20 },
  iosCard: { flex: 1, padding: 20 },
  head: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 12 },
  title: { flex: 1, fontSize: 24, fontWeight: "600" },
  close: { minHeight: 44, minWidth: 44, paddingHorizontal: 16, justifyContent: "center", alignItems: "center", borderWidth: 1, borderRadius: 999 },
  status: { marginTop: 8, fontSize: 15 },
  facts: { marginVertical: 16, gap: 10 },
  row: { flexDirection: "row", gap: 16 },
  key: { width: 84, fontSize: 15 },
  val: { flex: 1, fontSize: 15 },
  weight: { flexDirection: "row", alignItems: "center", gap: 8 },
  swatch: { width: 10, height: 10, borderRadius: 2 },
  topicsTitle: { marginBottom: 8, fontSize: 13, fontWeight: "500" },
  chips: { flexDirection: "row", flexWrap: "wrap", gap: 6 },
  chip: { paddingVertical: 4, paddingHorizontal: 10, borderRadius: 999, overflow: "hidden", fontSize: 13 },
});
