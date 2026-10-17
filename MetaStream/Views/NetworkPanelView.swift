import Charts
import SwiftUI

/// In-app network panel (sheet from the HUD): bitrate, drops, downtime and what the connection is doing.
/// Flat on purpose -- no material, no gradients; it is for the streamer's eyes, never on stream.
struct NetworkPanelView: View {
    @EnvironmentObject var streamer: Streamer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statusLine
                if streamer.live {
                    figures
                    NetChart(samples: streamer.net.samples)
                    session
                } else {
                    Text("Go live to see bitrate and drops.").font(.footnote).foregroundStyle(.gray)
                }
                network
                if streamer.live, !streamer.srtlaLinks.isEmpty { links }
                if streamer.live { changes }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationBackground(.black)
    }

    // MARK: status

    private var statusLine: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let (text, color) = status(ctx.date)
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(text).font(.headline.monospacedDigit())
            }
        }
    }

    private func status(_ now: Date) -> (String, Color) {
        guard streamer.live else { return ("Not live", .gray) }
        if let since = streamer.connectedSince {
            return ("Connected · " + Streamer.fmtClock(now.timeIntervalSince(since)), .green)
        }
        return ("Reconnecting · down " + Streamer.fmtClock(streamer.downtimeNow(now).current), .orange)
    }

    // MARK: figures

    private var figures: some View {
        HStack(alignment: .top, spacing: 24) {
            figure("Sending", NetworkStats.fmtKbps(streamer.kbps))
            figure("Target", NetworkStats.fmtKbps(streamer.currentBitrateKbps),
                   small: "max " + NetworkStats.fmtKbps(streamer.bitrateCeilingKbps))
            figure("Video", "\(streamer.fps) fps")
        }
    }

    private func figure(_ label: String, _ value: String, small: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.gray)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            if let small { Text(small).font(.caption2.monospacedDigit()).foregroundStyle(.gray) }
        }
    }

    // MARK: sections

    private var session: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            section("Session") {
                row("Drops", "\(streamer.drops)")
                row("Downtime", Streamer.fmtClock(streamer.downtimeNow(ctx.date).total))
                if streamer.drops > 0, let d = streamer.net.lastDropAt {
                    HStack {
                        Text("Last drop").foregroundStyle(.gray)
                        Spacer()
                        (Text(d, style: .relative) + Text(" ago")).monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private var network: some View {
        section("Network") {
            row("Connection", streamer.netPath.label)
            row("Status", streamer.netPath.status)
            if streamer.netPath.constrained { row("Low Data Mode", "on", .orange) }
            if streamer.netPath.expensive { row("Metered", "yes", .orange) }
        }
    }

    private var links: some View {
        section("Bonding links · last 10 s") {
            ForEach(streamer.srtlaLinks) { l in
                row(l.label + (l.backup ? " (backup)" : ""), l.up ? "\(l.share)%" : "down", l.up ? .white : .orange)
            }
        }
    }

    private var changes: some View {
        section("Bitrate changes") {
            if streamer.net.changes.isEmpty {
                Text("None yet").font(.footnote).foregroundStyle(.gray)
            }
            ForEach(streamer.net.changes.reversed()) { c in
                HStack(spacing: 10) {
                    Text(c.at.formatted(date: .omitted, time: .standard)).foregroundStyle(.gray)
                    Text((c.up ? "↑ " : "↓ ") + NetworkStats.fmtKbps(c.kbps)).foregroundStyle(c.up ? .green : .orange)
                    Text(c.reason).foregroundStyle(.white).lineLimit(1)
                }
                .font(.footnote.monospacedDigit())
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.gray)
            content()
        }
    }

    private func row(_ label: String, _ value: String, _ color: Color = .white) -> some View {
        HStack {
            Text(label).foregroundStyle(.gray)
            Spacer()
            Text(value).foregroundStyle(color).monospacedDigit()
        }
        .font(.subheadline)
    }
}

extension Streamer {
    /// Downtime so far: cumulative total (including the outage in progress) and the current outage alone.
    func downtimeNow(_ now: Date) -> (total: TimeInterval, current: TimeInterval) {
        let current = downSince.map { now.timeIntervalSince($0) } ?? 0
        return (downtime + current, current)
    }
}

/// Last 2 minutes: sent (solid) vs target (dashed step), with backed-up seconds in orange and down seconds in red.
private struct NetChart: View {
    let samples: [NetSample]

    private var yMax: Double {
        Double(max(samples.map { max($0.kbps, $0.target) }.max() ?? 0, 500)) * 1.15
    }

    /// Seconds ago for sample i (0 = newest).
    private func x(_ i: Int) -> Double { Double(i - (samples.count - 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            legend
            Chart {
                ForEach(Array(samples.enumerated()), id: \.offset) { i, s in
                    if s.down || s.congested {
                        RectangleMark(xStart: .value("t0", x(i) - 0.5), xEnd: .value("t1", x(i) + 0.5),
                                      yStart: .value("lo", 0), yEnd: .value("hi", yMax))
                            .foregroundStyle(s.down ? Color.red.opacity(0.35) : Color.orange.opacity(0.3))
                    }
                }
                ForEach(Array(samples.enumerated()), id: \.offset) { i, s in
                    LineMark(x: .value("t", x(i)), y: .value("kbps", s.target), series: .value("s", "target"))
                        .interpolationMethod(.stepEnd)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(Color.gray)
                }
                ForEach(Array(samples.enumerated()), id: \.offset) { i, s in
                    LineMark(x: .value("t", x(i)), y: .value("kbps", s.kbps), series: .value("s", "sent"))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(Color.white)
                }
            }
            .chartXScale(domain: -119.0...0.0)
            .chartYScale(domain: 0...yMax)
            .chartXAxis {
                AxisMarks(values: [-90.0, -60.0, -30.0, 0.0]) { v in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel {
                        if let d = v.as(Double.self) { Text(d == 0 ? "now" : "\(Int(d))s") }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel {
                        if let d = v.as(Double.self) { Text("\(Int(d))") }
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 160)
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            Text("kbps · last 2 min").foregroundStyle(.gray)
            Spacer()
            Text("sent").foregroundStyle(.white)
            Text("target").foregroundStyle(.gray)
            Text("backed up").foregroundStyle(.orange)
            Text("down").foregroundStyle(.red)
        }
        .font(.caption2)
    }
}
