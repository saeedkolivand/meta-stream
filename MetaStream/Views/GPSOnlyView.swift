import SwiftUI

/// iPhone screen while it only shares GPS with the iPad (GPSShare): no camera, chat or preview, so backgrounded it is
/// just location + a UDP responder. Stopping sharing brings the camera screen back.
struct GPSOnlyView: View {
    @ObservedObject private var share = GPSShare.shared
    @AppStorage("gpsShare") private var gpsShare = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "location.fill").font(.system(size: 56)).foregroundStyle(.blue)
            Text("Sharing GPS with iPad").font(.title2.bold())
            // TimelineView: "12 s ago" ticks without anything publishing.
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(spacing: 6) {
                    Text(share.latest.map { "Fix ±\(Int($0.accuracy)) m, \(ago($0.time, ctx.date))" } ?? "Waiting for a GPS fix…")
                    Text(share.lastAsked.map { "iPad last asked \(ago($0, ctx.date))" } ?? "iPad hasn't asked yet")
                }
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            Text("Camera and chat are off. You can lock the phone or leave the app.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Button("Stop sharing") {
                gpsShare = false
                GPSShare.shared.setEnabled(false)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func ago(_ t: Date, _ now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(t)))
        return s < 60 ? "\(s) s ago" : "\(s / 60) min ago"
    }
}
