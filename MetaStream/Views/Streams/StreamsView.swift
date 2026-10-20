import SwiftUI

/// Settings > Streams: every recorded stream session, newest first, each opening its Session report.
struct StreamsView: View {
    @State private var records: [SessionRecord] = []

    var body: some View {
        List {
            ForEach(records) { record in
                NavigationLink { SessionReportView(record: record) } label: { row(record) }
            }
            .onDelete { offsets in
                offsets.map { records[$0] }.forEach { SessionLog.delete($0) }
                records.remove(atOffsets: offsets)
            }
        }
        .overlay { if records.isEmpty { Text("No streams recorded yet").foregroundStyle(.secondary) } }
        .navigationTitle("Streams")
        .onAppear { records = SessionLog.all() }
    }

    private func row(_ record: SessionRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(record.start.formatted(date: .abbreviated, time: .shortened))
            Text("\(LivePostText.duration(record.duration)) · peak \(record.peakViewers) · \(record.donationCount) donations")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
