import SwiftUI

/// Settings › Donate page: where the public donate page lives and the key the app uses to push the live goal to it.
struct DonatePageSettingsView: View {
    @ObservedObject private var page = DonatePagePublisher.shared
    @AppStorage("donatePageURL") private var pageURL = DonatePagePublisher.defaultURL
    @State private var pageKey = ""

    var body: some View {
        Form {
            Section {
                TextField("Page URL", text: $pageURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                // Never loaded back into the field: the saved key stays in the Keychain, the field only takes a new one.
                SecureField(page.hasToken ? "Key saved (enter a new one to replace)" : "Page key", text: $pageKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save") { page.setToken(pageKey); pageKey = ""; page.request() }.buttonStyle(.borderless).disabled(pageKey.isEmpty)
                TimelineView(.periodic(from: .now, by: 5)) { _ in
                    Text(page.statusText).font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text("Donate page") } footer: {
                Text("Your donate page shows this goal live. Set the same key on Cloudflare (GOAL_TOKEN).")
            }
        }
        .navigationTitle("Donate page")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pageURL) { _, _ in page.request() }
    }
}
