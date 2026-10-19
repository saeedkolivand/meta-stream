import SwiftUI

/// Pre-go-live check of title / category / tags for each connected Kick/Twitch account. Reuses the
/// Stream Manager's adapters (load/apply/search); "Ask before going live" turns the sheet off.
struct StreamInfoSheet: View {
    let onGoLive: () -> Void
    @EnvironmentObject var platforms: Platforms
    @Environment(\.dismiss) private var dismiss
    @AppStorage("askStreamInfo") private var ask = true

    @State private var drafts: [String: StreamInfoDraft] = [:]
    @State private var originals: [String: StreamInfoDraft] = [:]
    @State private var failed: [String] = []   // platform names whose apply did not succeed
    @State private var busy = false

    private var ids: [String] { ["kick", "twitch"].filter { PlatformAdapter.all[$0]?.connected(platforms) == true } }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(ids, id: \.self) { id in
                    StreamInfoFields(id: id, draft: Binding(get: { drafts[id] ?? StreamInfoDraft() }, set: { drafts[id] = $0 }))
                }
                Section {
                    Toggle("Ask before going live", isOn: $ask)
                } footer: {
                    if !failed.isEmpty { Text("\(failed.joined(separator: ", ")) not updated: \(platforms.status)").foregroundStyle(.orange) }
                }
            }
            .navigationTitle("Stream info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(failed.isEmpty ? "Go live" : "Go live anyway") { go() }.bold().disabled(busy)
                }
            }
            .onAppear(perform: load)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

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
        // After a failed apply the button means "anyway": don't retry, just start.
        guard failed.isEmpty else { dismiss(); onGoLive(); return }
        busy = true
        Task {
            var bad: [String] = []
            for id in ids {
                guard let a = PlatformAdapter.all[id], let d = drafts[id], let o = originals[id], changed(d, o) else { continue }
                await a.apply(platforms, d)
                // PlatformFlow.mutate leaves "<Platform> ... updated" in status on success, the error text otherwise.
                if !platforms.status.hasSuffix("updated") { bad.append(a.name) }
            }
            busy = false
            if bad.isEmpty { dismiss(); onGoLive() } else { failed = bad }
        }
    }

    private func changed(_ d: StreamInfoDraft, _ o: StreamInfoDraft) -> Bool {
        d.title != o.title || d.category != o.category || StreamInfoDraft.cleanTags(d.tags) != StreamInfoDraft.cleanTags(o.tags)
    }
}

/// One platform's editable title / category search / tags.
private struct StreamInfoFields: View {
    let id: String
    @Binding var draft: StreamInfoDraft
    @EnvironmentObject var platforms: Platforms
    @State private var search = ""
    @State private var results: [StreamCategory] = []

    var body: some View {
        Section(PlatformAdapter.all[id]?.name ?? id) {
            TextField("Title", text: $draft.title, axis: .vertical).lineLimit(1...3)
            HStack { Text("Category").foregroundStyle(.secondary); Spacer(); Text(draft.category?.name ?? "—").lineLimit(1) }
            TextField("Search category…", text: $search)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onChange(of: search) { _, q in
                    Task { results = id == "kick" ? await platforms.kickSearch(q) : await platforms.twitchSearch(q) }
                }
            ForEach(results) { c in
                Button { draft.category = c; search = ""; results = [] } label: {
                    HStack { Text(c.name); Spacer(); if c == draft.category { Image(systemName: "checkmark") } }
                }
            }
            TextField("Tags, comma separated", text: $draft.tags)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }
}
