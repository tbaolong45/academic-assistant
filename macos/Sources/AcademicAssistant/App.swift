import Combine
import ServiceManagement
import SwiftUI

@main
struct AcademicAssistantApp: App {
    init() {
        if CommandLine.arguments.contains("--self-check") { runSelfCheck() }
        if CommandLine.arguments.contains("--doc-check") { // dates found in downloaded PDFs, from the cached sync (no network)
            let t0 = Date.now, subjects = MoodleCache.load()?.subjects ?? []
            let found = MaterialStore.documentEvents(subjects)
            for s in subjects { print("\(s.code): \(found[s.id]?.count ?? 0) dates; e.g. \(found[s.id]?.prefix(2).map { $0.title.prefix(70) } ?? [])") }
            if let i = CommandLine.arguments.firstIndex(of: "--doc-check"), i + 1 < CommandLine.arguments.count { // optional filter text
                let q = CommandLine.arguments[i + 1].lowercased()
                let kinds = KindCache.load()
                for e in found.values.joined() where e.title.lowercased().contains(q) || q == "*" {
                    let k = kinds[Jev.id(e.classifyText)].map { "\($0.kind.label) \(String(format: "%.2f", $0.confidence))" } ?? "unclassified"
                    print("  \(e.date.formatted(date: .abbreviated, time: .shortened))  [\(k)]  \(e.title.prefix(90))")
                }
            }
            print(String(format: "scanned in %.1fs", Date.now.timeIntervalSince(t0)))
            exit(0)
        }
        if CommandLine.arguments.contains("--moodle-check") { runMoodleCheck() }
        if CommandLine.arguments.contains("--mail-check") { runMailCheck() }
        if CommandLine.arguments.contains("--login-check") { print("login item:", SMAppService.mainApp.status.rawValue, "(1 = enabled, 2 = needs approval)"); exit(0) }
    }

    @StateObject private var nav = Nav()
    @StateObject private var store = Store()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Academic Assistant", id: "main") { // first scene: the one macOS opens at launch
            RootView(nav: nav)
                .environmentObject(nav)
                .environmentObject(store)
                .frame(minWidth: 640, minHeight: 480)
                .preferredColorScheme(.dark)
                .fontDesign(.monospaced)
                .tint(Tech.neon)
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Go") {
                Button("Overview") { nav.go(.overview) }.keyboardShortcut("0")
                Button("Deadlines") { nav.go(.week) }.keyboardShortcut("d")
                Button("Calendar") { nav.go(.calendar) }.keyboardShortcut("l")
                ForEach(Array(store.subjects.prefix(9).enumerated()), id: \.element.id) { i, s in
                    Button(s.name) { nav.go(.course(s.id)) }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
                Divider()
                Button("Sync now") { store.syncNow() }.keyboardShortcut("r").disabled(!store.isConnected || store.syncing)
            }
        }
        // Menu-bar icon: the app keeps syncing (and notifying) with its window closed.
        MenuBarExtra("Academic Assistant", systemImage: "graduationcap") { MenuBarMenu().environmentObject(store) }
    }
}

private struct MenuBarMenu: View {
    @EnvironmentObject private var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Academic Assistant") { openWindow(id: "main"); NSApp.activate() }
        Button(store.syncing ? "Syncing…" : "Sync now") { store.syncNow() }.disabled(!store.isConnected || store.syncing)
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}

enum Route: Hashable { case overview, week, calendar, course(String) }

/// Current sidebar selection, shared with the Go menu's keyboard shortcuts.
@MainActor final class Nav: ObservableObject {
    @Published var selection: Route? = .overview
    @Published var focus: String? // an announcement to show (Announcement.key) when the course opens
    func go(_ r: Route) { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { selection = r } }
    /// Opens a course; with `announcement`, on its Announcements tab at that post.
    func open(_ course: String, announcement: String? = nil) { focus = announcement; go(.course(course)) }
}

struct RootView: View {
    @ObservedObject var nav: Nav
    @EnvironmentObject private var store: Store
    @Local private var hovered: Route?
    @Local private var showConnect = false

    var body: some View {
        NavigationSplitView {
            // Rows are buttons with our own neon highlight: List(selection:) forces the system blue accent.
            List {
                sidebarRow(.overview, index: 0) {
                    Image(systemName: "square.grid.2x2").foregroundStyle(Tech.neon)
                    Text("Overview")
                }
                sidebarRow(.week, index: 1) {
                    Image(systemName: "calendar.day.timeline.left").foregroundStyle(Tech.neon)
                    Text("Deadlines")
                    Spacer(minLength: 4)
                    Text("\(store.board.between(weekStart(of: .now), weekStart(of: .now).addingTimeInterval(7 * 86_400)).count)").foregroundStyle(Tech.text2).monospacedDigit()
                }
                sidebarRow(.calendar, index: 2) {
                    Image(systemName: "calendar").foregroundStyle(Tech.neon)
                    Text("Calendar")
                    Spacer(minLength: 4)
                    let today = OutlookCalendar.occurrences(store.calendarItems, from: Calendar.current.startOfDay(for: .now),
                                                            to: Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)).count
                    Text(store.calendarItems.isEmpty ? "—" : "\(today) today").foregroundStyle(Tech.text2).monospacedDigit()
                }
                Section {
                    ForEach(Array(store.subjects.enumerated()), id: \.element.id) { i, s in
                        sidebarRow(.course(s.id), index: i + 3) {
                            Circle().fill(s.hue.palette.accent).frame(width: 8, height: 8)
                                .shadow(color: s.hue.palette.accent, radius: 4)
                            Text(s.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(s.runningGrade.map { String(format: "%.1f", $0) } ?? "—")
                                .foregroundStyle(Tech.text2).monospacedDigit()
                        }
                    }
                } header: {
                    Text("COURSES").font(.caption2.weight(.semibold)).tracking(1.6).foregroundStyle(Tech.text3)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tech.panel)
            .safeAreaInset(edge: .bottom) { SyncFooter { showConnect = true } }
            .navigationSplitViewColumnWidth(min: 280, ideal: 290, max: 360) // monospaced names need the room
        } detail: {
            ZStack {
                TechBackground()
                Group {
                    switch nav.selection {
                    case .course(let id): if let s = store.subject(id) { CourseView(subject: s) }
                    case .week: WeekView(open: { nav.go(.course($0)) })
                    case .calendar: CalendarView()
                    default: HomeView(open: { nav.go(.course($0)) })
                    }
                }
                .id(nav.selection)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: nav.selection)
        }
        .sheet(isPresented: $showConnect) { ConnectView() }
        // Live data replaces the course ids (and disconnecting restores the sample ones): leave a vanished course.
        .onChange(of: store.subjects.map(\.id)) { if case .course(let id) = nav.selection, store.subject(id) == nil { nav.go(.overview) } }
    }

    private func sidebarRow(_ route: Route, index: Int, @ViewBuilder content: () -> some View) -> some View {
        let selected = nav.selection == route
        return Button { nav.go(route) } label: {
            HStack(spacing: 8) { content() }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .offset(x: hovered == route && !selected ? 3 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(selected ? Tech.neon.opacity(0.12) : hovered == route ? Tech.panelHi : .clear)
                        .overlay(alignment: .leading) {
                            if selected {
                                Capsule().fill(Tech.neon).frame(width: 3).padding(.vertical, 6)
                                    .shadow(color: Tech.neon, radius: 6)
                            }
                        }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: hovered)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selected)
        .onHover { hovered = $0 ? route : (hovered == route ? nil : hovered) }
        .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
        .stagger(index)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Keeps the app alive when its window is closed and registers it to open at login (approve once in System Settings ▸ Login Items).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !CommandLine.arguments.contains(where: { $0.hasPrefix("--") }) { try? SMAppService.mainApp.register() }
    }
}
