import Combine
import SwiftUI

/// Top-level settings. iPhone: a searchable list pushing one screen at a time; iPad: a sidebar and the selected screen
/// beside it. Both draw from SettingsCatalog (Views/Settings/), which is also what search reads, so a row and its search
/// hits can't drift apart. Every @AppStorage key is unchanged by this layout.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize
    @EnvironmentObject private var platforms: Platforms
    @EnvironmentObject private var streamer: Streamer
    @State private var query = ""
    @State private var wrappedPending = false
    @State private var path: [String] = []           // iPhone: the pushed page ids
    @State private var selection: String? = "ingest" // iPad: the page in the detail column
    @State private var refresh = 0                   // bumped when a default changes so values and issues redraw

    private var ctx: SettingsContext { SettingsContext(platforms: platforms, streamer: streamer) }
    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Group {
            if hSize == .regular { splitLayout } else { stackLayout }
        }
        .preferredColorScheme(.dark)
        .onAppear { wrappedPending = WrappedStore.pendingMonth(records: SessionLog.all()) != nil }
        // Debounced: a slider in a detail screen writes defaults continuously, and issue checks read the Keychain.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)) { _ in refresh &+= 1 }
    }

    // MARK: layouts

    private var stackLayout: some View {
        NavigationStack(path: $path) {
            List {
                if trimmed.isEmpty { browseSections(open: { path.append($0) }) } else { searchSections(open: { path.append($0) }) }
            }
            .navigationTitle("Settings")
            .searchable(text: $query, prompt: "Search settings")
            .navigationDestination(for: String.self) { id in
                SettingsCatalog.pages().first { $0.id == id }?.destination() ?? AnyView(EmptyView())
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            List(selection: $selection) {
                if trimmed.isEmpty { browseSections(open: { selection = $0 }) } else { searchSections(open: { selection = $0 }) }
            }
            .navigationTitle("Settings")
            .searchable(text: $query, placement: .sidebar, prompt: "Search settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        } detail: {
            NavigationStack {
                if let page = SettingsCatalog.pages().first(where: { $0.id == selection }) { page.destination().id(page.id) }
            }
        }
    }

    // MARK: sections

    @ViewBuilder
    private func browseSections(open: @escaping (String) -> Void) -> some View {
        let _ = refresh   // read so a changed default redraws the values and issues
        let pages = SettingsCatalog.pages()
        let issues = SettingsReadiness.issues(ctx)
        Section { ReadinessCard(chips: SettingsReadiness.chips(ctx), issues: issues, open: open) }
        ForEach(SettingsGroup.allCases, id: \.self) { group in
            Section(group.title) {
                ForEach(pages.filter { $0.group == group }) { page in
                    pageRow(page, issues: issues.filter { $0.pageID == page.id }.count)
                }
            }
        }
    }

    @ViewBuilder
    private func pageRow(_ page: SettingsPage, issues: Int) -> some View {
        let row = SettingsPageRow(page: page, value: page.value(ctx), issues: issues,
                                  wrappedPending: wrappedPending && page.id == "streams")
        if hSize == .regular { row.tag(page.id) } else { NavigationLink(value: page.id) { row } }
    }

    @ViewBuilder
    private func searchSections(open: @escaping (String) -> Void) -> some View {
        let pages = SettingsCatalog.pages()
        let screens = pages.filter { SettingsCatalog.matches(trimmed, in: $0.title + " " + $0.group.title) }
        let items = SettingsCatalog.items(pages: pages).filter {
            SettingsCatalog.matches(trimmed, in: $0.title + " " + $0.path + " " + $0.keywords)
        }
        if screens.isEmpty && items.isEmpty {
            ContentUnavailableView.search(text: trimmed)
        }
        if !screens.isEmpty {
            Section("Screens") { ForEach(screens) { pageRow($0, issues: 0) } }
        }
        if !items.isEmpty {
            Section("Settings") {
                ForEach(items) { item in
                    if let page = pages.first(where: { $0.id == item.pageID }) { SettingsItemRow(item: item, page: page, open: open) }
                }
            }
        }
    }
}
