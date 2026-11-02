import { Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { useTheme } from "@/theme";

// Opening a course page directly still puts Home underneath, so there is always a way back.
export const unstable_settings = { initialRouteName: "index" };

export default function RootLayout() {
  const t = useTheme();
  return (
    <>
      <StatusBar style="auto" />
      <Stack
        screenOptions={{
          headerStyle: { backgroundColor: t.surface },
          headerTintColor: t.ink,
          headerShadowVisible: false,
          contentStyle: { backgroundColor: t.surface },
        }}
      >
        <Stack.Screen name="index" options={{ title: "Academic Assistant", headerLargeTitle: true }} />
        <Stack.Screen name="subjects/[id]" options={{ title: "", headerBackTitle: "Courses" }} />
      </Stack>
    </>
  );
}
