import { useState, type ReactNode } from "react";
import { Pressable, ScrollView, Text, View } from "react-native";
import { Link, Stack, useLocalSearchParams } from "expo-router";
import { ScoreChart } from "@/components/ScoreChart";
import { getSubject } from "@/data";
import { hueOf, page, useTheme } from "@/theme";

const tabs = [
  ["scores", "Scores"],
  ["assignments", "Assignments"],
  ["materials", "Lectures & Material"],
  ["announcements", "Announcements"],
] as const;

// Hermes and browsers disagree on the comma ("Fri, 30 Oct" vs "Fri 30 Oct"); drop it either way.
const fmt = (iso: string) =>
  new Date(iso).toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" }).replace(/,/g, "");

// Shape marker per source; the text label is always shown next to it.
const marker = { Moodle: { borderRadius: 3 }, Outlook: {}, Teams: { transform: [{ rotate: "45deg" }] } } as const;

export default function SubjectScreen() {
  const t = useTheme();
  const { id } = useLocalSearchParams<{ id: string }>();
  const subject = getSubject(String(id));
  const [tab, setTab] = useState<(typeof tabs)[number][0]>("scores");

  if (!subject) {
    return (
      <View style={[page, { paddingVertical: 32, gap: 12 }]}>
        <Stack.Screen options={{ title: "Not found" }} />
        <Text style={{ color: t.ink, fontSize: 17, fontWeight: "600" }}>Course not found</Text>
        <Link href="/" style={{ color: t.ink2, fontSize: 16, paddingVertical: 14 }}>
          Back to courses
        </Link>
      </View>
    );
  }

  const { accent, tint } = hueOf(t, subject.hue);
  const s = {
    list: { backgroundColor: t.card, borderWidth: 1, borderColor: t.hairline, borderRadius: 14, overflow: "hidden" },
    row: { flexDirection: "row", alignItems: "center", gap: 12, minHeight: 56, paddingVertical: 12, paddingHorizontal: 14 },
    name: { color: t.ink, fontSize: 15, fontWeight: "500" },
    meta: { color: t.ink3, fontSize: 13, marginTop: 2 },
    pill: { flexDirection: "row", alignItems: "center", gap: 6, paddingVertical: 3, paddingHorizontal: 10, borderRadius: 999, borderWidth: 1, borderColor: t.hairline },
    pillText: { color: t.ink2, fontSize: 12, fontWeight: "500" },
  } as const;
  const sep = (i: number) => (i > 0 ? { borderTopWidth: 1, borderTopColor: t.hairline } : null);

  const row = (key: string, i: number, title: string, meta: string, tag: ReactNode) => (
    <View key={key} style={[s.row, sep(i)]}>
      <View style={{ flex: 1, minWidth: 0 }}>
        <Text style={s.name}>{title}</Text>
        <Text style={s.meta}>{meta}</Text>
      </View>
      {tag}
    </View>
  );

  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={[page, { paddingTop: 8, paddingBottom: 32 }]}>
      <Stack.Screen options={{ title: subject.name }} />

      <View style={{ borderLeftWidth: 4, borderLeftColor: accent, paddingLeft: 12, paddingVertical: 2, marginBottom: 16 }}>
        <Text style={{ color: t.ink3, fontSize: 13, letterSpacing: 0.3 }}>{subject.code}</Text>
      </View>

      <View accessibilityRole="tablist" style={{ flexDirection: "row", borderBottomWidth: 1, borderBottomColor: t.hairline, marginBottom: 16 }}>
        {tabs.map(([key, label]) => {
          const selected = key === tab;
          return (
            <Pressable
              key={key}
              accessibilityRole="tab"
              accessibilityState={{ selected }}
              onPress={() => setTab(key)}
              style={{
                flex: 1,
                minHeight: 48,
                alignItems: "center",
                justifyContent: "center",
                paddingHorizontal: 2,
                paddingVertical: 4,
                borderBottomWidth: 3,
                borderBottomColor: selected ? accent : "transparent",
                marginBottom: -1,
              }}
            >
              <Text numberOfLines={2} style={{ textAlign: "center", fontSize: 14, lineHeight: 17, color: selected ? t.ink : t.ink2, fontWeight: selected ? "700" : "400" }}>
                {label}
              </Text>
            </Pressable>
          );
        })}
      </View>

      {tab === "scores" && <ScoreChart subject={subject} />}

      {tab === "assignments" && (
        <View style={s.list}>
          {subject.assignments.map((x, i) =>
            row(x.title, i, x.title, `Due ${fmt(x.due)}`,
              <View style={[s.pill, x.status === "Open" && { backgroundColor: tint, borderColor: "transparent" }]}>
                <Text style={[s.pillText, x.status === "Open" && { color: t.ink }]}>{x.status}</Text>
              </View>,
            ),
          )}
        </View>
      )}

      {tab === "materials" && (
        <View style={s.list}>
          {subject.materials.map((x, i) =>
            row(x.title, i, x.title, fmt(x.date),
              <View style={s.pill}>
                <Text style={s.pillText}>{x.kind}</Text>
              </View>,
            ),
          )}
        </View>
      )}

      {tab === "announcements" && (
        <View style={s.list}>
          {subject.announcements.map((x, i) =>
            row(x.title, i, x.title, `${x.from} · ${fmt(x.date)}`,
              <View style={s.pill}>
                <View style={[{ width: 6, height: 6, backgroundColor: t.ink3 }, marker[x.source]]} />
                <Text style={s.pillText}>{x.source}</Text>
              </View>,
            ),
          )}
        </View>
      )}
    </ScrollView>
  );
}
