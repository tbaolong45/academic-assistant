import { router } from "expo-router";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { runningGrade, stillToCome, subjects, thisWeek } from "@/data";
import { hueOf, page, useTheme } from "@/theme";

function when(iso: string, now: number) {
  const n = Math.round((Date.parse(iso) - now) / 864e5);
  const rel = n <= 0 ? "today" : n === 1 ? "tomorrow" : `in ${n} days`;
  const date = new Date(iso).toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" });
  return `${rel} · ${date.replace(/,/g, "")}`;
}

// Pressable + router.push rather than <Link asChild>: on web, Link's slot drops a Pressable's style function.
const open = (id: string) => router.push({ pathname: "/subjects/[id]", params: { id } });

export default function Home() {
  const t = useTheme();
  const now = Date.now();
  const muted = { color: t.ink3, fontSize: 13 };
  const heading = [styles.heading, { color: t.ink3 }];

  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={[page, styles.content]}>
      <Text style={heading} accessibilityRole="header">This week</Text>
      {thisWeek(3, now).map(({ subject, assessment }) => {
        const label = `${assessment.name}${assessment.type !== assessment.name ? ` · ${assessment.type}` : ""}`;
        const whenText = when(assessment.date, now);
        return (
          <Pressable
              key={subject.id + assessment.id}
              onPress={() => open(subject.id)}
              accessibilityRole="link"
              accessibilityLabel={`${subject.name}, ${label}, ${whenText}, ${assessment.weight}% of grade`}
              style={({ pressed }) => [styles.row, { backgroundColor: t.card, borderColor: t.hairline }, pressed && styles.pressed]}
            >
              <View style={[styles.marker, { backgroundColor: hueOf(t, subject.hue).accent }]} />
              <View style={styles.rowMain}>
                <Text style={muted}>{subject.name}</Text>
                <Text style={[styles.strong, { color: t.ink }]}>
                  {assessment.name}
                  {assessment.type !== assessment.name && <Text style={muted}> · {assessment.type}</Text>}
                </Text>
                <Text style={muted}>{whenText}</Text>
              </View>
              <Text style={[styles.weight, { color: t.ink2 }]}>{assessment.weight}% of grade</Text>
            </Pressable>
        );
      })}

      <Text style={heading} accessibilityRole="header">Your courses</Text>
      {subjects.map((subject) => {
        const h = hueOf(t, subject.hue);
        const grade = runningGrade(subject);
        const left = stillToCome(subject);
        const gradeText = grade === null ? "No grades yet" : `${grade.toFixed(1)}%`;
        return (
          <Pressable
              key={subject.id}
              onPress={() => open(subject.id)}
              accessibilityRole="link"
              accessibilityLabel={`${subject.name}, running grade ${gradeText}, ${left}% still to come`}
              style={({ pressed }) => [styles.card, { backgroundColor: h.tint, borderColor: t.hairline }, pressed && styles.pressed]}
            >
              <View style={[styles.edge, { backgroundColor: h.accent }]} />
              <View style={styles.cardHead}>
                <Text style={[styles.strong, { color: t.ink }]}>{subject.name}</Text>
                <Text style={muted}>{subject.code}</Text>
              </View>
              <Text style={[styles.grade, { color: t.ink }]}>{gradeText}</Text>
              <Text style={muted}>Running grade</Text>
              <View style={[styles.meter, { backgroundColor: h.shades[0] }]}>
                <View style={{ width: `${100 - left}%`, height: "100%", backgroundColor: h.accent }} />
              </View>
              <Text style={muted}>
                {100 - left}% done · {left}% of grade still to come
              </Text>
              <View style={styles.chevron}>
                <Text style={{ color: t.ink3, fontSize: 24 }}>›</Text>
              </View>
            </Pressable>
        );
      })}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: { paddingBottom: 32, gap: 10 },
  heading: { marginTop: 14, fontSize: 13, fontWeight: "600", textTransform: "uppercase", letterSpacing: 0.8 },
  strong: { fontSize: 15, fontWeight: "600" },
  pressed: { opacity: 0.7 },
  row: { flexDirection: "row", alignItems: "center", gap: 12, minHeight: 44, paddingVertical: 12, paddingHorizontal: 14, borderWidth: StyleSheet.hairlineWidth, borderRadius: 12 },
  marker: { width: 10, height: 10, borderRadius: 5 },
  rowMain: { flex: 1, minWidth: 0 },
  weight: { fontSize: 13, fontWeight: "600", textAlign: "right" },
  card: { gap: 2, minHeight: 44, paddingVertical: 16, paddingLeft: 20, paddingRight: 40, borderWidth: StyleSheet.hairlineWidth, borderRadius: 14, overflow: "hidden" },
  edge: { position: "absolute", left: 0, top: 0, bottom: 0, width: 6 },
  cardHead: { flexDirection: "row", flexWrap: "wrap", alignItems: "baseline", columnGap: 8, rowGap: 4 },
  grade: { marginTop: 8, fontSize: 34, fontWeight: "700", letterSpacing: -0.6, fontVariant: ["tabular-nums"] },
  meter: { height: 6, marginTop: 10, marginBottom: 4, borderRadius: 3, overflow: "hidden" },
  chevron: { position: "absolute", right: 16, top: 0, bottom: 0, justifyContent: "center" },
});
