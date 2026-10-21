import SwiftUI

/// Settings > Streams: every recorded stream session, newest first and grouped by month, each opening its Session report.
struct StreamsView: View {
    @State private var records: [SessionRecord] = []
    @State private var bestSlot: String?
    @State private var reviewMonth: String?

    /// Months newest first, each with its sessions newest first (`records` is already sorted that way).
    private var months: [(key: String, sessions: [SessionRecord])] {
        var out: [(key: String, sessions: [SessionRecord])] = []
        for record in records {
            let key = WrappedBuilder.monthKey(record.start)
            if let index = out.firstIndex(where: { $0.key == key }) {
                out[index].sessions.append(record)
            } else {
                out.append((key, [record]))
            }
        }
        return out
    }

    var body: some View {
        List {
            if let month = WrappedStore.pendingMonth(records: records) { wrappedCard(month) }
            if !records.isEmpty { heatmapCard }
            ForEach(months, id: \.key) { month in
                Section(WrappedStore.monthName(month.key)) {
                    ForEach(month.sessions) { record in
                        NavigationLink { SessionReportView(record: record) } label: { StreamRow(record: record) }
                    }
                    .onDelete { offsets in delete(offsets.map { month.sessions[$0] }) }
                }
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
        .onAppear {
            records = SessionLog.all()
            bestSlot = HeatmapView.bestSlot(records)
        }
    }

    private func delete(_ doomed: [SessionRecord]) {
        doomed.forEach { SessionLog.delete($0) }
        records.removeAll { rec in doomed.contains { $0.start == rec.start } }
        bestSlot = HeatmapView.bestSlot(records)
    }

    private func wrappedCard(_ month: String) -> some View {
        NavigationLink { WrappedReviewView(month: month, records: records) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(WrappedStore.monthName(month)) Wrapped is ready").font(.headline)
                Text("Review before it goes on your page").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .listRowBackground(Color(red: 0.102, green: 0.165, blue: 0.251))
    }

    private var heatmapCard: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("When your viewers show up").font(.headline)
                HeatmapView(records: records)
                if let bestSlot { Text("Best slot: \(bestSlot)").font(.subheadline) }
            }
            .padding(.vertical, 4)
        }
    }
}
