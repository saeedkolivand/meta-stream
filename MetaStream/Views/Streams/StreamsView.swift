import SwiftUI

/// Settings > Streams: every recorded stream session, newest first, each opening its Session report.
struct StreamsView: View {
    @State private var records: [SessionRecord] = []
    @State private var reviewMonth: String?

    var body: some View {
        List {
            if let month = WrappedStore.pendingMonth(records: records) {
                NavigationLink { WrappedReviewView(month: month, records: records) } label: {
                    Text("\(WrappedStore.monthName(month)) Wrapped is ready to review")
                }
            }
            if !records.isEmpty { Section { HeatmapView(records: records) } }
            ForEach(records) { record in
                NavigationLink { SessionReportView(record: record) } label: { row(record) }
            }
            .onDelete { offsets in
                offsets.map { records[$0] }.forEach { SessionLog.delete($0) }
                records.remove(atOffsets: offsets)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Wrapped…") {
                    ForEach(WrappedStore.allMonths(records), id: \.self) { month in
                        Button(WrappedStore.monthName(month)) { reviewMonth = month }
                    }
                }
                .disabled(records.isEmpty)
            }
        }
        .navigationDestination(item: $reviewMonth) { WrappedReviewView(month: $0, records: records) }
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
