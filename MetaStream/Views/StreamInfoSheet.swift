import SwiftUI
import UIKit

/// Pre-go-live check of title / category / tags for each connected Kick/Twitch account, prefilled with what was
/// entered last time. Reuses the Stream Manager's adapters (load/apply/search); "Ask before going live" turns it off.
struct StreamInfoSheet: View {
    let onGoLive: () -> Void
    @EnvironmentObject var platforms: Platforms
    @Environment(\.dismiss) private var dismiss
    @AppStorage("askStreamInfo") private var ask = true
    @AppStorage("streamInfoShared") private var shared = true   // one title + tags for every platform

    @State private var drafts: [String: StreamInfoDraft] = [:]
    @State private var originals: [String: StreamInfoDraft] = [:]
    @State private var failed: [String: String] = [:]   // platform id -> why its update didn't go through
    @State private var working: String?                  // platform being updated right now

    private var ids: [String] { ["kick", "twitch"].filter { PlatformAdapter.all[$0]?.connected(platforms) == true } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    if ids.count > 1 {
                        Toggle(isOn: $shared) {
                            Label("Same title and tags everywhere", systemImage: "link")
                        }
                        .onChange(of: shared) { _, on in if on, let first = ids.first { mirror(from: first) } }
                        .padding(14).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    }
                    ForEach(ids, id: \.self) { id in
                        PlatformCard(id: id, draft: binding(id), edited: edited(id), failure: failed[id],
                                     editsText: !(shared && ids.count > 1 && id != ids.first))
                    }
                    Toggle("Ask before going live", isOn: $ask)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(.horizontal, 14).padding(.top, 4)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { goButton }
            .navigationTitle("Stream info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear(perform: load)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .interactiveDismissDisabled(working != nil)
    }

    // MARK: pieces

    private var header: some View {
        HStack(spacing: 8) {
            Text("Going live on").font(.subheadline).foregroundStyle(.secondary)
            ForEach(ids, id: \.self) { id in
                HStack(spacing: 5) {
                    Circle().fill(PlatformCard.brand(id)).frame(width: 8, height: 8)
                    Text(PlatformAdapter.all[id]?.name ?? id).font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(PlatformCard.brand(id).opacity(0.15), in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    private var goButton: some View {
        VStack(spacing: 8) {
            if !failed.isEmpty {
                Label("Some changes didn't save. You can still go live.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: go) {
                HStack(spacing: 10) {
                    if let w = working {
                        ProgressView().tint(.black)
                        Text("Saving to \(PlatformAdapter.all[w]?.name ?? w)…")
                    } else {
                        Image(systemName: "dot.radiowaves.left.and.right")
                        Text(failed.isEmpty ? (anyEdited ? "Save and go live" : "Go live") : "Go live anyway")
                    }
                }
                .font(.headline).foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(failed.isEmpty ? Color.green : Color.orange, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(working != nil)
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
        .background(.ultraThinMaterial)
    }

    // MARK: drafts

    private func binding(_ id: String) -> Binding<StreamInfoDraft> {
        Binding(get: { drafts[id] ?? StreamInfoDraft() }, set: { new in
            drafts[id] = new
            failed[id] = nil
            if shared, id == ids.first { mirror(from: id) }
        })
    }

    /// The first platform's title and tags copied to the others (each keeps its own category: ids differ per platform).
    private func mirror(from id: String) {
        guard let src = drafts[id] else { return }
        for other in ids where other != id {
            drafts[other]?.title = src.title
            drafts[other]?.tags = src.tags
        }
    }

    private func edited(_ id: String) -> Bool {
        guard let d = drafts[id], let o = originals[id] else { return false }
        return d.title != o.title || d.category != o.category || StreamInfoDraft.cleanTags(d.tags) != StreamInfoDraft.cleanTags(o.tags)
    }

    private var anyEdited: Bool { ids.contains { edited($0) } }

    private func load() {
        let options: [(id: String, name: String)] = platforms.twitchLabelCatalog.isEmpty
            ? Platforms.twitchLabelIDs.map { (id: $0, name: $0) } : platforms.twitchLabelCatalog
        for id in ids {
            guard let d = PlatformAdapter.all[id]?.load(platforms, options) else { continue }
            originals[id] = d   // the platform's current values, so a saved prefill counts as a change to apply
            var p = d
            if let s = UserDefaults.standard.data(forKey: "lastStreamInfo.\(id)"), let v = try? JSONDecoder().decode(Saved.self, from: s) {
                p.title = v.title; p.tags = v.tags
                p.category = v.categoryID.map { StreamCategory(id: $0, name: v.categoryName) }
            }
            drafts[id] = p
        }
    }

    /// What the user entered last time, restored as the next prefill.
    private struct Saved: Codable { var title: String; var categoryID: String?; var categoryName: String; var tags: String }

    private func save() {
        for id in ids {
            guard let d = drafts[id] else { continue }
            let v = Saved(title: d.title, categoryID: d.category?.id, categoryName: d.category?.name ?? "", tags: d.tags)
            if let data = try? JSONEncoder().encode(v) { UserDefaults.standard.set(data, forKey: "lastStreamInfo.\(id)") }
        }
    }

    private func go() {
        save()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // After a failed update the button means "anyway": don't retry, just start.
        guard failed.isEmpty else { dismiss(); onGoLive(); return }
        Task {
            var bad: [String: String] = [:]
            for id in ids where edited(id) {
                guard let a = PlatformAdapter.all[id], let d = drafts[id] else { continue }
                working = id
                await a.apply(platforms, d)
                // PlatformFlow.mutate leaves "<Platform> ... updated" in status on success, the error text otherwise.
                if !platforms.status.hasSuffix("updated") { bad[id] = platforms.status }
            }
            working = nil
            if bad.isEmpty { dismiss(); onGoLive() } else { failed = bad }
        }
    }
}

/// One platform's title, category search and tags, as a card in the platform's colour.
private struct PlatformCard: View {
    let id: String
    @Binding var draft: StreamInfoDraft
    let edited: Bool
    let failure: String?
    let editsText: Bool   // false while "same title and tags" copies them from the first platform
    @EnvironmentObject var platforms: Platforms
    @State private var search = ""
    @State private var results: [StreamCategory] = []
    @State private var searching = false
    @State private var picking = false
    @State private var newTag = ""
    @State private var lookup: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    static func brand(_ id: String) -> Color {
        id == "kick" ? Color(red: 0.33, green: 0.99, blue: 0.09) : Color(red: 0.57, green: 0.27, blue: 1)
    }

    private var titleLimit: Int { 140 }
    private var tags: [String] { StreamInfoDraft.cleanTags(draft.tags) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Circle().fill(Self.brand(id)).frame(width: 10, height: 10)
                Text(PlatformAdapter.all[id]?.name ?? id).font(.headline)
                Spacer()
                if edited { Text("Edited").font(.caption.weight(.semibold)).foregroundStyle(Self.brand(id)) }
            }

            field("Title") {
                if editsText {
                    TextField("What's happening?", text: $draft.title, axis: .vertical).lineLimit(1...3)
                } else {
                    Text(draft.title.isEmpty ? "—" : draft.title).foregroundStyle(.secondary)
                }
                Text("\(draft.title.count)/\(titleLimit)").font(.caption2.monospacedDigit())
                    .foregroundStyle(draft.title.count > titleLimit ? Color.red : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            field("Category") {
                Button { picking.toggle(); searchFocused = picking } label: {
                    HStack {
                        Text(draft.category?.name ?? "Choose a category").foregroundStyle(draft.category == nil ? .secondary : .primary)
                        Spacer()
                        Image(systemName: picking ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if picking { categorySearch }
            }

            field("Tags") {
                if editsText {
                    Flow(spacing: 6) {
                        ForEach(tags, id: \.self) { t in
                            HStack(spacing: 4) {
                                Text(t).font(.subheadline)
                                Button { remove(t) } label: { Image(systemName: "xmark").font(.caption2.weight(.bold)) }
                                    .buttonStyle(.plain).accessibilityLabel("Remove \(t)")
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Self.brand(id).opacity(0.18), in: Capsule())
                        }
                    }
                    if tags.count < 10 {
                        TextField(tags.isEmpty ? "Add a tag" : "Add another", text: $newTag)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .submitLabel(.done).onSubmit(addTag)
                    }
                } else {
                    Text(tags.isEmpty ? "—" : tags.joined(separator: ", ")).foregroundStyle(.secondary)
                }
            }

            if let failure {
                Label(failure, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(edited ? Self.brand(id).opacity(0.5) : .clear, lineWidth: 1))
    }

    private var categorySearch: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(PlatformAdapter.all[id]?.name ?? "") categories", text: $search)
                    .focused($searchFocused)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if searching { ProgressView().controlSize(.small) }
            }
            .padding(10).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .onChange(of: search) { _, q in find(q) }
            ForEach(results) { c in
                Button { draft.category = c; search = ""; results = []; picking = false } label: {
                    HStack {
                        Text(c.name).lineLimit(1)
                        Spacer()
                        if c == draft.category { Image(systemName: "checkmark").foregroundStyle(Self.brand(id)) }
                    }
                    .padding(.vertical, 10).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
            if !searching, !search.isEmpty, results.isEmpty {
                Text("No categories match").font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
            }
        }
    }

    /// Debounced: a search per keystroke would race and flash stale results.
    private func find(_ q: String) {
        lookup?.cancel()
        let text = q.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { results = []; searching = false; return }
        searching = true
        lookup = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let found = id == "kick" ? await platforms.kickSearch(text) : await platforms.twitchSearch(text)
            guard !Task.isCancelled else { return }
            results = Array(found.prefix(8))
            searching = false
        }
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: " ")
        newTag = ""
        guard !t.isEmpty, !tags.contains(t), tags.count < 10 else { return }
        draft.tags = (tags + [t]).joined(separator: ", ")
    }

    private func remove(_ t: String) { draft.tags = tags.filter { $0 != t }.joined(separator: ", ") }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).kerning(0.6)
            content()
        }
    }
}

/// Left-to-right wrapping row (tag chips).
private struct Flow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0, x + z.width > maxW { x = 0; y += row + spacing; row = 0 }
            x += z.width + spacing
            row = max(row, z.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxW), height: subviews.isEmpty ? 0 : y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + z.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + spacing
            row = max(row, z.height)
        }
    }
}
