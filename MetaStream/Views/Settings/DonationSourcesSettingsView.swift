import SwiftUI

/// Settings › Donation sources: one key per donation site (status, secure key, Save).
struct DonationSourcesSettingsView: View {
    @ObservedObject private var hub = DonationHub.shared

    var body: some View {
        Form {
            Section {
                ForEach(DonationHub.Site.allCases, id: \.self) { site in
                    SiteKeyRow(site: site, status: hub.status[site] ?? "")
                }
            } header: { Text("Donation sources") }
        }
        .navigationTitle("Donation sources")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A donation site: status, its key (secure) and Save.
private struct SiteKeyRow: View {
    let site: DonationHub.Site
    let status: String
    @ObservedObject private var hub = DonationHub.shared
    @State private var key = ""
    @State private var widget = ""
    @State private var overlay = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(site.title).font(.headline)
            if !status.isEmpty { Text(status).font(.footnote).foregroundStyle(.secondary) }
            SecureField(site.keyLabel, text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
            Text(site.help).font(.footnote).foregroundStyle(.secondary)
            Button("Save") { DonationHub.shared.setKey(site, key) }.buttonStyle(.borderless)
            if site == .donofa {
                Divider()
                if !hub.widgetStatus.isEmpty { Text("Widget: " + hub.widgetStatus).font(.footnote).foregroundStyle(.secondary) }
                SecureField("Widget link (alerts)", text: $widget).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("Paste a Donofa widget or widget-group link. Donofa then sends its alerts here (one at a time, like in OBS); "
                     + "real donations still count through your API key.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Save") { DonationHub.shared.setDonofaWidget(widget) }.buttonStyle(.borderless)
            }
            if site == .reymit {
                Divider()
                if !hub.reymitOverlayStatus.isEmpty { Text(hub.reymitOverlayStatus).font(.footnote).foregroundStyle(.secondary) }
                SecureField("Overlay link (test alerts)", text: $overlay).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("Paste the Reymit overlay link. Reymit's test button only reaches the overlay; tests play the alert and never count.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Save") { DonationHub.shared.setReymitOverlay(overlay) }.buttonStyle(.borderless)
            }
        }
        .onAppear {
            key = DonationHub.shared.key(site)
            widget = DonationHub.shared.donofaWidget()
            overlay = DonationHub.shared.reymitOverlay()
        }
    }
}
