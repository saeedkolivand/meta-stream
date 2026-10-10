// Health monitoring + diagnostics: battery/thermal observers, probes, device descriptions.
import Foundation
import AVFoundation
import UIKit
import Network
import HaishinKit
import MWDATCore

extension Streamer {

    // MARK: dual camera

    func logFaceCamHealth() {
        let before = faceCamFrames.count
        Task {
            try? await Task.sleep(for: .seconds(2))
            let topology = await Self.sessionTopology(mixer)
            applog("stream", "dual camera: session \(topology)")
            applog("stream", "dual camera: \(faceCamFrames.count - before) face-cam frames in 2 s, offscreen=\(offscreenOn), canvas=\(Int(dualCamCanvas.width))x\(Int(dualCamCanvas.height)), overlay=\(overlayObject != nil), visible=\(dualCamActive && !dualCamHidden && !blurWanted)")
        }
    }

    /// The capture session's connections as "source->output enabled/active", for the face-cam health log.
    static func sessionTopology(_ mixer: MediaMixer) async -> String {
        let box = Box("")
        await mixer.configuration { (session: AVCaptureSession) in
            box.value = session.connections.map { c in
                let src = c.inputPorts.map { "\($0.sourceDeviceType?.rawValue.replacingOccurrences(of: "AVCaptureDeviceType", with: "") ?? $0.mediaType.rawValue)/\($0.sourceDevicePosition == .front ? "front" : "back")" }.joined(separator: "+")
                return "\(src)->\(c.output.map { String(describing: type(of: $0)) } ?? "nil") en=\(c.isEnabled) act=\(c.isActive)"
            }.joined(separator: ", ")
        }
        return box.value
    }

    /// AVCaptureMultiCamSession.hardwareCost of the mixer's current session (> 1.0 = the configuration
    /// can't run); 0 for a non-multicam session. MediaMixer.configuration hands the raw AVCaptureSession to
    /// a closure on the mixer's own actor, so the value comes back through a box.
    static func multiCamCost(_ mixer: MediaMixer) async -> Float {
        let box = Box(Float(0))
        await mixer.configuration { (session: AVCaptureSession) in
            box.value = (session as? AVCaptureMultiCamSession)?.hardwareCost ?? 0
        }
        return box.value
    }

    /// First sign a LIVE connection is down: starts the downtime clock, counts the drop, speaks + buzzes once.
    /// No-op if already marked — a failed reconnect attempt re-enters this after the poll loop already did.
    func markDropped() {
        guard downSince == nil else { return }
        downSince = Date()
        drops += 1
        rtmpState = "reconnecting"
        applog("stream", "connection dropped, retrying", error: true)
        speaker?.startRepeating(id: "rtmp", text: "stream dropped")   // re-speaks itself at 30s/60s/2min
        haptic(.error)
    }

    /// Beyond Speaker's own 30s/60s/2min repeat cycle: one more nudge at 2 min down, another at 5 — so silence
    /// never stretches on forever. Covers a drop AND a stream that never connected in the first place.
    func checkEscalation() {
        guard let since = downSince else { return }
        let elapsed = Date().timeIntervalSince(since)
        if elapsed >= 300, !escalated5m {
            escalated5m = true
            speaker?.speakSystem("stream still down after 5 minutes, may need a manual restart")
        } else if elapsed >= 120, !escalated2m {
            escalated2m = true
            speaker?.speakSystem("stream still down after 2 minutes")
        }
    }

    /// Backgrounded (screen off, glasses-only) haptics are a no-op anyway; skip the allocation.
    func haptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard UIApplication.shared.applicationState == .active else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    // MARK: health monitoring

    /// Phone battery + thermal only matter while actually streaming (a 30-45 min walk is exactly when
    /// the phone throttles or the battery runs down), so they're only observed live → stopLive() rather
    /// than leaving isBatteryMonitoringEnabled and two NotificationCenter observers on for the app's life.
    func startHealthMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        updatePhoneBattery()
        thermal = ProcessInfo.processInfo.thermalState
        batteryObserver = NotificationCenter.default.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updatePhoneBattery() }
        }
        thermalObserver = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.thermal = ProcessInfo.processInfo.thermalState }
        }
        // ponytail: only picks up the glasses connected at the moment Go Live is pressed — matches the
        // file's documented usual order (start glasses, then go live). A glasses connect/reconnect mid-
        // stream won't retroactively start this stream; upgrade path is hooking it off session creation
        // in startGlasses() instead if that gap turns out to matter.
        if let id = session?.deviceId {
            glassesThermalTask = Task { [weak self] in
                for await state in Wearables.shared.deviceStateStream(for: id) {
                    self?.glassesThermal = state.thermalLevel
                }
            }
        }
    }

    func stopHealthMonitoring() {
        if let o = batteryObserver { NotificationCenter.default.removeObserver(o) }
        if let o = thermalObserver { NotificationCenter.default.removeObserver(o) }
        batteryObserver = nil; thermalObserver = nil
        UIDevice.current.isBatteryMonitoringEnabled = false
        glassesThermalTask?.cancel()
        glassesThermalTask = nil
        glassesThermal = nil
    }

    func updatePhoneBattery() {
        let level = UIDevice.current.batteryLevel   // -1 while unknown/monitoring just turned on
        phoneBattery = level < 0 ? nil : Int(level * 100)
    }

    func checkPhoneBattery() {
        guard let b = phoneBattery, b < 15, !warnedPhoneBattery else { return }
        warnedPhoneBattery = true
        speaker?.speakSystem("phone battery fifteen percent")
    }

    func checkThermal() {
        // ThermalState isn't Comparable; rawValue order is nominal < fair < serious < critical.
        let serious = thermal.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        // Heat and congestion both want less bitrate, and encoding is the expensive part — cap the ceiling
        // at wherever the AIMD loop is *after* one forced step down, so up-steps can't climb back until
        // thermal clears. Edge-triggered on thermalCeilingKbps == nil so this fires once per entry, not once
        // per tick. Gated on phoneEncodes, same as adaptBitrate — no knob to turn during hevc passthrough.
        if serious, thermalCeilingKbps == nil, phoneEncodes, live {
            thermalCeilingKbps = currentBitrateKbps   // close the edge-trigger now; refined once the drop lands
            Task {
                await self.stepBitrate(up: false, reason: "thermal \(self.thermal)")
                self.thermalCeilingKbps = self.currentBitrateKbps
            }
        } else if !serious {
            thermalCeilingKbps = nil
        }
        guard serious, !warnedThermal else { return }
        warnedThermal = true
        speaker?.speakSystem("phone getting hot")
    }

    /// ThermalLevel is Equatable, not Comparable/rawValue-ordered — switch on the cases the 0.9 docs list
    /// (unknown, none, light, moderate, severe, critical, emergency, shutdown) instead of guessing an order.
    func checkGlassesThermal() {
        guard let t = glassesThermal, !warnedGlassesThermal else { return }
        switch t {
        case .severe, .critical, .emergency, .shutdown:
            warnedGlassesThermal = true
            speaker?.speakSystem("glasses getting hot")
        default: break
        }
    }

    // MARK: devices status line

    func watchDevices(_ ids: [DeviceIdentifier]) {
        let list = ids.compactMap { Wearables.shared.deviceForIdentifier($0) }
        deviceTokens = list.flatMap { d in
            [d.addLinkStateListener { [weak self] _ in Task { @MainActor in self?.describeDevices() } },
             d.addCompatibilityListener { [weak self] _ in Task { @MainActor in self?.describeDevices() } }]
        }
        describeDevices()
    }

    func describeDevices() {
        let list = Wearables.shared.devices.compactMap { Wearables.shared.deviceForIdentifier($0) }
            .map { "\($0.nameOrId()) \($0.linkState) \($0.compatibility())" }
        devices = list.isEmpty ? "none" : list.joined(separator: ", ")
    }

    /// Diagnostic: current network path + TCP reachability of the ingest host over the default route and over cellular only.
    static func netProbe(_ urlString: String) async {
        guard let u = URL(string: urlString), let host = u.host else { return }
        let port = UInt16(u.port ?? (u.scheme == "rtmps" ? 443 : 1935))
        let path = await withCheckedContinuation { (c: CheckedContinuation<NWPath, Never>) in
            let m = NWPathMonitor(); m.pathUpdateHandler = { p in c.resume(returning: p); m.cancel() }; m.start(queue: .global())
        }
        let ifaces = path.availableInterfaces.map { "\($0.name):\($0.type)" }.joined(separator: ",")
        applog("stream", "net path status=\(path.status) wifi=\(path.usesInterfaceType(.wifi)) cell=\(path.usesInterfaceType(.cellular)) expensive=\(path.isExpensive) ifaces=[\(ifaces)]")
        for (label, required) in [("default", nil), ("cellular", NWInterface.InterfaceType.cellular)] {
            let params = NWParameters.tcp
            if let required { params.requiredInterfaceType = required }
            let conn = NWConnection(host: .init(host), port: .init(rawValue: port)!, using: params)
            let result: String = await withCheckedContinuation { c in
                let once = Box(false)
                conn.stateUpdateHandler = { st in
                    switch st {
                    case .ready: if once.fire() { c.resume(returning: "ready via \(conn.currentPath?.availableInterfaces.first.map { "\($0.type)" } ?? "?")") }
                    case .failed(let e): if once.fire() { c.resume(returning: "failed: \(e)") }
                    case .waiting(let e): applog("stream", "probe \(label) waiting: \(e)")
                    default: break
                    }
                }
                conn.start(queue: .global())
                DispatchQueue.global().asyncAfter(deadline: .now() + 6) { if once.fire() { c.resume(returning: "timeout 6 s") } }
            }
            conn.cancel()
            applog("stream", "probe \(label) \(host):\(port) -> \(result)", error: !result.hasPrefix("ready"))
        }
    }
}
