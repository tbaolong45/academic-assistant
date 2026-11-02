import { useState } from "react";
import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { AssessmentSheet, fmtDate } from "@/components/AssessmentSheet";
import { band, bandLabels, runningGrade, stillToCome, type Assessment, type Subject } from "@/data";
import { hueOf, useTheme } from "@/theme";

const PLOT = 160; // plot height
const HEAD = 20; // room above the plot for the value label of a 100% bar
const ticks = [0, 25, 50, 75, 100];

export function ScoreChart({ subject }: { subject: Subject }) {
  const t = useTheme();
  const { shades } = hueOf(t, subject.hue);
  const [sel, setSel] = useState<Assessment | null>(null);
  const [table, setTable] = useState(false);
  const grade = runningGrade(subject);
  const toCome = stillToCome(subject);
  const soFar = subject.assessments.reduce((n, x) => n + x.weight, 0) - toCome;

  return (
    <View>
      <Text style={[s.kicker, { color: t.ink2 }]}>Running grade</Text>
      <Text style={[s.hero, { color: t.ink }]}>{grade === null ? "—" : `${grade.toFixed(1)}%`}</Text>
      <Text style={[s.sub, { color: t.ink3 }]}>
        from {soFar}% of the grade so far · {toCome}% still to come
      </Text>

      {/* Chart: fixed y-axis + gridlines; only the columns scroll sideways. */}
      <View style={s.chart}>
        <View style={s.yAxis} importantForAccessibility="no-hide-descendants" accessibilityElementsHidden>
          {ticks.map((v) => (
            <Text key={v} style={[s.tick, { bottom: (PLOT * v) / 100 - 6, color: t.ink3 }]}>{v}%</Text>
          ))}
        </View>
        <View style={s.plotArea}>
          <View style={s.grid} pointerEvents="none">
            {ticks.map((v) => (
              <View key={v} style={[s.gridline, { bottom: (PLOT * v) / 100, backgroundColor: t.hairline }]} />
            ))}
          </View>
          <ScrollView horizontal contentContainerStyle={s.cols}>
            {subject.assessments.map((a) => {
              const up = a.score === undefined;
              const shade = shades[band(a.weight)];
              return (
                <Pressable
                  key={a.id}
                  onPress={() => setSel(a)}
                  accessibilityRole="button"
                  accessibilityLabel={`${a.name}: ${up ? "upcoming" : `scored ${a.score}%`}, ${a.weight}% of course grade`}
                  // `hovered` is passed by react-native-web only.
                  style={(st) => [s.col, (st.pressed || (st as { hovered?: boolean }).hovered) && { backgroundColor: t.hairline }]}
                >
                  <View style={s.track}>
                    <Text style={[s.value, { color: up ? t.ink3 : t.ink2 }]} numberOfLines={1}>
                      {up ? "upcoming" : `${a.score}%`}
                    </Text>
                    <View
                      style={[
                        s.bar,
                        up ? { height: PLOT, borderWidth: 2, borderColor: shade } : { height: (PLOT * a.score!) / 100, backgroundColor: shade },
                      ]}
                    />
                  </View>
                  <Text style={[s.name, { color: t.ink2 }]} numberOfLines={2}>{a.name}</Text>
                  <Text style={[s.weight, { color: t.ink3 }]}>{a.weight}%</Text>
                </Pressable>
              );
            })}
          </ScrollView>
        </View>
      </View>

      <View style={s.legend}>
        <Text style={[s.legendTitle, { color: t.ink3 }]}>Shade = share of course grade</Text>
        {bandLabels.map((label, i) => (
          <View key={label} style={s.legendItem}>
            <View style={[s.swatch, { backgroundColor: shades[i] }]} />
            <Text style={[s.legendText, { color: t.ink2 }]}>{label}</Text>
          </View>
        ))}
        <View style={s.legendItem}>
          <View style={[s.swatch, { borderWidth: 2, borderColor: t.ink3 }]} />
          <Text style={[s.legendText, { color: t.ink2 }]}>Upcoming</Text>
        </View>
      </View>

      <Pressable
        onPress={() => setTable(!table)}
        accessibilityRole="button"
        accessibilityLabel={table ? "Hide table" : "Show as table"}
        accessibilityState={{ expanded: table }}
        style={s.toggle}
      >
        <Text style={{ color: t.ink2, fontSize: 13 }}>{table ? "▾ Hide table" : "▸ Show as table"}</Text>
      </Pressable>
      {table && (
        <View>
          {[["Name", "Date", "Score", "Weight", "Status"], ...subject.assessments.map((a) => [
            a.name,
            fmtDate(a.date),
            a.score === undefined ? "—" : `${a.score}%`,
            `${a.weight}%`,
            a.score === undefined ? "Upcoming" : "Graded",
          ])].map((row, r) => (
            <View key={r} style={[s.tr, { borderBottomColor: t.hairline }]}>
              {row.map((cell, c) => (
                <Text key={c} style={[s.td, { flex: colFlex[c], color: r ? t.ink : t.ink2, fontWeight: r ? "400" : "500" }]}>{cell}</Text>
              ))}
            </View>
          ))}
        </View>
      )}

      <AssessmentSheet assessment={sel} hue={subject.hue} onClose={() => setSel(null)} />
    </View>
  );
}

const colFlex = [1.4, 1.6, 0.9, 0.9, 1.1];

const s = StyleSheet.create({
  kicker: { fontSize: 13 },
  hero: { marginVertical: 2, fontSize: 44, fontWeight: "600", letterSpacing: -0.9, fontVariant: ["tabular-nums"] },
  sub: { marginBottom: 20, fontSize: 13 },
  chart: { flexDirection: "row" },
  yAxis: { width: 36, height: PLOT, marginTop: HEAD },
  tick: { position: "absolute", right: 6, fontSize: 11, lineHeight: 12, fontVariant: ["tabular-nums"] },
  plotArea: { flex: 1 },
  grid: { position: "absolute", top: HEAD, left: 0, right: 0, height: PLOT },
  gridline: { position: "absolute", left: 0, right: 0, height: 1 },
  cols: { flexGrow: 1 },
  col: { flexGrow: 1, flexBasis: 0, minWidth: 76, alignItems: "center", gap: 2, paddingHorizontal: 4, paddingBottom: 8, borderRadius: 8 },
  track: { height: HEAD + PLOT, marginBottom: 6, alignSelf: "stretch", alignItems: "center", justifyContent: "flex-end" },
  value: { marginBottom: 4, fontSize: 11, lineHeight: 12 },
  bar: { width: 24, borderTopLeftRadius: 4, borderTopRightRadius: 4 },
  name: { fontSize: 12, lineHeight: 15, textAlign: "center" },
  weight: { fontSize: 11 },
  legend: { flexDirection: "row", flexWrap: "wrap", rowGap: 6, columnGap: 14, marginTop: 12 },
  legendTitle: { flexBasis: "100%", fontSize: 12 },
  legendItem: { flexDirection: "row", alignItems: "center", gap: 6 },
  legendText: { fontSize: 12 },
  swatch: { width: 10, height: 10, borderRadius: 2 },
  toggle: { minHeight: 44, justifyContent: "center", marginTop: 8, alignSelf: "flex-start" },
  tr: { flexDirection: "row", gap: 6, paddingVertical: 6, borderBottomWidth: StyleSheet.hairlineWidth },
  td: { fontSize: 13 },
});
