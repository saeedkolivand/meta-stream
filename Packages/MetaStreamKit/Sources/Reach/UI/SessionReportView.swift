import SwiftUI

/// The Session report (CONTEXT.md "Session report"): the streamer's private account of one stream, never posted anywhere.
/// Flat dark cards; the pieces live in the Report*.swift files next to this one.
struct SessionReportView: View {
    let record: SessionRecord
    @State private var history: [SessionRecord] = []
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let insights = ReportInsights(record: record, history: history)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(insights)
                ReportOverviewCard(insights: insights)
                ReportTiles(insights: insights)
                ReportChartCard(insights: insights)
                if !record.moments.isEmpty { ReportMomentsCard(moments: record.moments) }
                if !record.chatterCounts.isEmpty || record.topDonor != nil { ReportAudienceCard(insights: insights) }
                ReportConnectionCard(insights: insights)
                Button("Delete this report", role: .destructive) { confirmDelete = true }
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 14)
            }
            .padding()
        }
        .navigationTitle("Session report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: insights.summary) { Label("Share", systemImage: "square.and.arrow.up") }
            }
        }
        .confirmationDialog("Delete this report?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete this report", role: .destructive) {
                SessionLog.delete(record)
                dismiss()
            }
        }
        .onAppear { history = SessionLog.all() }
    }

    private func header(_ insights: ReportInsights) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(insights.title).font(.title.bold())
            Text(insights.dateLine).foregroundStyle(.secondary)
            // ponytail: chips scroll sideways instead of wrapping; three short chips at most.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip).font(.footnote).padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    /// Platform, where and how far, camera; only the ones that were recorded.
    private var chips: [String] {
        var place = record.cities?.joined(separator: ", ") ?? ""
        if let meters = record.distanceMeters, meters > 0 {
            place += (place.isEmpty ? "" : " · ") + String(format: "%.1f km", meters / 1000)
        }
        return [record.platform ?? "", place, record.camera ?? ""].filter { !$0.isEmpty }
    }
}
