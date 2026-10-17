// Remote control: a subset of the obs-websocket v5 server, so Stream Deck, Touch Portal and Streamer.bot drive the app as
// if it were OBS (adr/0004). Local network only, behind a password. NW callbacks run on a private queue and hop to the main
// actor; everything below that line is plain main-actor code.
// ponytail: JSON only (no msgpack), no studio mode, no per-input audio beyond Mic, unknown requests answer 204.
import AVFoundation
import Combine
import CryptoKit
import Foundation
import Network

@MainActor
final class ObsServer {
    static let shared = ObsServer()
    static let port: UInt16 = 4455
    private static let chars = Array("abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let supported = ["GetVersion", "GetSceneList", "GetCurrentProgramScene", "SetCurrentProgramScene",
        "GetStudioModeEnabled", "GetStreamStatus", "StartStream", "StopStream", "ToggleStream", "GetRecordStatus",
        "StartRecord", "StopRecord", "ToggleRecord", "GetInputList", "GetInputMute", "SetInputMute", "ToggleInputMute",
        "TriggerMediaInputAction", "GetHotkeyList"]

    private final class Client {
        let conn: NWConnection
        let challenge = ObsServer.random()
        let salt = ObsServer.random()
        var ok = false, alive = true
        var subs = 2047   // OBS default: everything but high-volume events
        init(_ c: NWConnection) { conn = c }
    }
    private typealias Res = (code: Int, comment: String?, data: [String: Any])

    private let q = DispatchQueue(label: "obs-ws")
    private var listener: NWListener?
    private var clients: [Client] = []
    private var bag = Set<AnyCancellable>()
    private var streamer: Streamer?
    private var password: String { UserDefaults.standard.string(forKey: "obsPassword") ?? "" }

    nonisolated static func random() -> String { Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString() }
    nonisolated static func randomPassword() -> String { String((0..<12).map { _ in chars.randomElement()! }) }

    /// base64(sha256(base64(sha256(password + salt)) + challenge)), per the obs-websocket spec.
    nonisolated static func auth(_ pw: String, salt: String, challenge: String) -> String {
        func h(_ s: String) -> String { Data(SHA256.hash(data: Data(s.utf8))).base64EncodedString() }
        return h(h(pw + salt) + challenge)
    }

    #if DEBUG
    /// Self-check: the worked example from the obs-websocket protocol document.
    nonisolated static func demo() {
        let a = auth("supersecretpassword", salt: "lM1GncleQOaCu9lT1yeUZhFYnqhsLLP1G5lAGo3ixaI=",
                     challenge: "+IxH4CnCiqpX1rM9scsNynZzbOe4KhDeYcTNS3PDaeY=")
        assert(a == "1Ct943GAT+6YQUUX47Ia/ncufilbe6+oD6lY+5kaCu4=", "obs-websocket auth mismatch: \(a)")
        applog("remote", "ObsServer.demo: auth check ok")
    }
    #endif

    /// (label, ip) for every IPv4 address a controller could reach: en* = Wi-Fi, bridge* = this device's hotspot.
    nonisolated static func addresses() -> [(String, String)] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return [] }
        defer { freeifaddrs(head) }
        var out: [(String, String)] = []
        var p = head
        while let a = p?.pointee {
            defer { p = a.ifa_next }
            let name = String(cString: a.ifa_name)
            guard let sa = a.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET), name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: buf)
            if !ip.hasPrefix("169.254") { out.append((name.hasPrefix("bridge") ? "Hotspot" : name == "en0" ? "Wi-Fi" : name, ip)) }
        }
        return out
    }

    // MARK: lifecycle

    /// Idempotent: makes the listener match the "obsServerOn" default. Call at launch and when the toggle changes.
    func sync(_ s: Streamer) {
        let d = UserDefaults.standard
        if d.bool(forKey: "obsServerOn") {
            if password.isEmpty { d.set(Self.randomPassword(), forKey: "obsPassword") }
            if listener == nil { start(s) }
        } else if listener != nil { stop() }
    }

    private func start(_ s: Streamer) {
        let p = NWParameters.tcp
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        ws.setClientRequestHandler(q) { subprotocols, _ in
            NWProtocolWebSocket.Response(status: .accept, subprotocol: subprotocols.contains("obswebsocket.json") ? "obswebsocket.json" : nil)
        }
        p.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        guard let l = try? NWListener(using: p, on: NWEndpoint.Port(integerLiteral: Self.port)) else {
            applog("remote", "listener could not be created", error: true); return
        }
        l.newConnectionHandler = { c in Task { @MainActor in self.accept(c) } }
        l.stateUpdateHandler = { st in
            if case .failed(let e) = st { applog("remote", "listener failed: \(e)", error: true) }
        }
        l.start(queue: q)
        listener = l; streamer = s
        observe(s)
        applog("remote", "obs-websocket listening on \(Self.port)")
    }

    private func stop() {
        listener?.cancel(); listener = nil
        clients.forEach { $0.conn.cancel() }; clients = []
        bag.removeAll(); streamer = nil
        applog("remote", "obs-websocket stopped")
    }

    /// Events come from the published values, so every path that changes them (app UI, remote, rotation) is covered.
    private func observe(_ s: Streamer) {
        let o = OverlayStore.shared
        s.$live.dropFirst().removeDuplicates().sink { self.event("StreamStateChanged", 64, Self.out($0)) }.store(in: &bag)
        s.$recordingSince.map { $0 != nil }.dropFirst().removeDuplicates()
            .sink { self.event("RecordStateChanged", 64, Self.out($0).merging(["outputPath": ""]) { a, _ in a }) }.store(in: &bag)
        s.$muted.dropFirst().removeDuplicates()
            .sink { self.event("InputMuteStateChanged", 8, ["inputName": "Mic", "inputUuid": "Mic", "inputMuted": $0]) }.store(in: &bag)
        o.$scene.dropFirst().removeDuplicates()
            .sink { self.event("CurrentProgramSceneChanged", 4, ["sceneName": $0, "sceneUuid": $0]) }.store(in: &bag)
        o.$pack.map { $0?.scenes.map(\.name) ?? [] }.dropFirst().removeDuplicates()
            .sink { _ in self.event("SceneListChanged", 4, ["scenes": self.sceneList()]) }.store(in: &bag)
    }

    // MARK: transport

    private func accept(_ c: NWConnection) {
        let cl = Client(c)
        clients.append(cl)
        c.stateUpdateHandler = { st in
            switch st {
            case .failed, .cancelled: Task { @MainActor in self.drop(cl) }
            default: break
            }
        }
        c.start(queue: q)
        send(cl, ["op": 0, "d": ["obsWebSocketVersion": "5.5.0", "rpcVersion": 1,
                                 "authentication": ["challenge": cl.challenge, "salt": cl.salt]]])
        receive(cl)
        applog("remote", "client connected")
    }

    private func receive(_ cl: Client) {
        cl.conn.receiveMessage { data, ctx, _, err in
            let meta = ctx?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            Task { @MainActor in
                if err != nil || meta?.opcode == .close { self.drop(cl); return }
                if meta?.opcode == .text, let data { await self.handle(cl, data) }
                if cl.alive { self.receive(cl) }
            }
        }
    }

    private func drop(_ cl: Client) {
        guard cl.alive else { return }
        cl.alive = false
        cl.conn.cancel()
        clients.removeAll { $0 === cl }
        applog("remote", "client gone")
    }

    private func send(_ cl: Client, _ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        let ctx = NWConnection.ContentContext(identifier: "obs", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
        cl.conn.send(content: data, contentContext: ctx, isComplete: true, completion: .idempotent)
    }

    /// obs-websocket close codes are 4000+ (4009 authentication failed, 4007 not identified).
    private func close(_ cl: Client, _ code: UInt16) {
        cl.ok = false
        let m = NWProtocolWebSocket.Metadata(opcode: .close)
        m.closeCode = .privateCode(code)
        let ctx = NWConnection.ContentContext(identifier: "obs", metadata: [m])
        cl.conn.send(content: nil, contentContext: ctx, isComplete: true, completion: .contentProcessed { _ in Task { @MainActor in self.drop(cl) } })
    }

    private func event(_ type: String, _ bit: Int, _ data: [String: Any]) {
        for cl in clients where cl.ok && cl.subs & bit != 0 {
            send(cl, ["op": 5, "d": ["eventType": type, "eventIntent": bit, "eventData": data]])
        }
    }

    // MARK: protocol

    private func handle(_ cl: Client, _ raw: Data) async {
        guard let m = try? JSONSerialization.jsonObject(with: raw) as? [String: Any], let op = m["op"] as? Int else { return close(cl, 4002) }
        let d = m["d"] as? [String: Any] ?? [:]
        switch op {
        case 1:
            guard d["authentication"] as? String == Self.auth(password, salt: cl.salt, challenge: cl.challenge) else {
                applog("remote", "authentication failed", error: true)
                return close(cl, 4009)
            }
            fallthrough
        case 3:
            guard cl.ok || op == 1 else { return close(cl, 4007) }
            cl.ok = true
            cl.subs = d["eventSubscriptions"] as? Int ?? 2047
            send(cl, ["op": 2, "d": ["negotiatedRpcVersion": 1]])
        case 6:
            guard cl.ok else { return close(cl, 4007) }
            send(cl, ["op": 7, "d": await response(d)])
        case 8:
            guard cl.ok else { return close(cl, 4007) }
            var results: [[String: Any]] = []
            for r in d["requests"] as? [[String: Any]] ?? [] { results.append(await response(r)) }
            send(cl, ["op": 9, "d": ["requestId": d["requestId"] ?? "", "results": results]])
        default: break
        }
    }

    private func response(_ d: [String: Any]) async -> [String: Any] {
        let type = d["requestType"] as? String ?? ""
        let r = await run(type, d["requestData"] as? [String: Any] ?? [:])
        var st: [String: Any] = ["result": r.code == 100, "code": r.code]
        if let c = r.comment { st["comment"] = c }
        var out: [String: Any] = ["requestType": type, "requestId": d["requestId"] ?? "", "requestStatus": st]
        if !r.data.isEmpty { out["responseData"] = r.data }
        return out
    }

    private static func out(_ on: Bool) -> [String: Any] {
        ["outputActive": on, "outputState": on ? "OBS_WEBSOCKET_OUTPUT_STARTED" : "OBS_WEBSOCKET_OUTPUT_STOPPED"]
    }
    private func ms(_ d: Date?) -> Int { d.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0 }
    private func tc(_ t: Int) -> String { String(format: "%02d:%02d:%02d.%03d", t / 3_600_000, t / 60_000 % 60, t / 1000 % 60, t % 1000) }
    /// OBS lists scenes bottom-to-top.
    private func sceneList() -> [[String: Any]] {
        OverlayStore.shared.scenes.map(\.name).reversed().enumerated().map { ["sceneIndex": $0, "sceneName": $1, "sceneUuid": $1] }
    }

    private func run(_ type: String, _ q: [String: Any]) async -> Res {
        guard let s = streamer else { return (600, "MetaStream is not ready", [:]) }
        let store = OverlayStore.shared
        let sounds = Sound.decode(UserDefaults.standard.string(forKey: "sounds") ?? "[]")
        let inputName = (q["inputName"] ?? q["inputUuid"]) as? String
        func ok(_ data: [String: Any] = [:]) -> Res { (100, nil, data) }
        func scene() -> [String: Any] {
            ["currentProgramSceneName": store.scene, "sceneName": store.scene, "currentProgramSceneUuid": store.scene, "sceneUuid": store.scene]
        }
        func startStream() -> Res {
            if s.live { return (500, "Stream is already running", [:]) }
            s.goLiveFromSettings(); return ok()
        }
        func stopStream() -> Res {
            if !s.live { return (501, "Stream is not running", [:]) }
            s.requestStop(); return ok()
        }
        func record(_ on: Bool) async -> Res {
            if on == (s.recordingSince != nil) { return (on ? 500 : 501, on ? "Record is already running" : "Record is not running", [:]) }
            if on { await s.startRecording() } else { await s.stopRecording() }
            if on && s.recordingSince == nil { return (702, "Recording could not start", [:]) }
            return ok(on ? [:] : ["outputPath": ""])   // ponytail: the file goes to Photos, so there is no path to give
        }
        func mic(_ set: (Bool) -> Bool) -> Res {
            guard let n = inputName else { return (300, "Missing inputName", [:]) }
            guard n == "Mic" else { return (600, "No input named \(n)", [:]) }
            let m = set(s.muted)
            s.setMuted(m)
            return ok(["inputMuted": m])
        }

        switch type {
        case "GetVersion":
            return ok(["obsVersion": "30.0.0", "obsWebSocketVersion": "5.5.0", "rpcVersion": 1, "availableRequests": Self.supported,
                       "supportedImageFormats": [String](), "platform": "ios", "platformDescription": "MetaStream"])
        case "GetSceneList":
            return ok(scene().merging(["currentPreviewSceneName": NSNull(), "currentPreviewSceneUuid": NSNull(), "scenes": sceneList()]) { a, _ in a })
        case "GetCurrentProgramScene":
            return ok(scene())
        case "SetCurrentProgramScene":
            guard let n = (q["sceneName"] ?? q["sceneUuid"]) as? String else { return (300, "Missing sceneName", [:]) }
            guard store.scenes.contains(where: { $0.name == n }) else { return (600, "No scene named \(n)", [:]) }
            s.selectScene(n); return ok()
        case "GetStudioModeEnabled":
            return ok(["studioModeEnabled": false])
        case "GetStreamStatus":
            let t = ms(s.liveSince)
            return ok(["outputActive": s.live, "outputReconnecting": s.downSince != nil, "outputTimecode": tc(t), "outputDuration": t,
                       "outputCongestion": 0, "outputBytes": 0, "outputSkippedFrames": 0, "outputTotalFrames": 0])
        case "StartStream": return startStream()
        case "StopStream": return stopStream()
        case "ToggleStream":
            let was = s.live
            let r = was ? stopStream() : startStream()
            return r.code == 100 ? ok(["outputActive": !was]) : r
        case "GetRecordStatus":
            let t = ms(s.recordingSince)
            return ok(["outputActive": s.recordingSince != nil, "outputPaused": false, "outputTimecode": tc(t), "outputDuration": t, "outputBytes": 0])
        case "StartRecord": return await record(true)
        case "StopRecord": return await record(false)
        case "ToggleRecord":
            let was = s.recordingSince != nil
            let r = await record(!was)
            return r.code == 100 ? ok(["outputActive": !was]) : r
        case "GetInputList":
            let kind = "coreaudio_input_capture"
            return ok(["inputs": [["inputName": "Mic", "inputUuid": "Mic", "inputKind": kind, "unversionedInputKind": kind]]
                       + sounds.map { ["inputName": $0.name, "inputUuid": $0.name, "inputKind": "ffmpeg_source", "unversionedInputKind": "ffmpeg_source"] }])
        case "GetInputMute":
            return mic { $0 }
        case "SetInputMute":
            guard let m = q["inputMuted"] as? Bool else { return (300, "Missing inputMuted", [:]) }
            return mic { _ in m }
        case "ToggleInputMute":
            return mic { !$0 }
        case "TriggerMediaInputAction":
            guard let n = inputName, let a = q["mediaAction"] as? String else { return (300, "Missing inputName or mediaAction", [:]) }
            guard let snd = sounds.first(where: { $0.name == n }) else { return (600, "No input named \(n)", [:]) }
            if a.hasSuffix("_RESTART") || a.hasSuffix("_PLAY") { SoundMix.shared.playSound(snd) }
            return ok()
        case "GetHotkeyList":
            return ok(["hotkeys": [String]()])
        default:
            return (204, "Not supported by MetaStream", [:])
        }
    }
}

extension Streamer {
    /// Go Live with the saved settings: the Go Live button and the remote's StartStream both land here.
    /// Keys and defaults mirror the old @AppStorage declarations in GoLiveControlsView.
    func goLiveFromSettings() {
        let d = UserDefaults.standard
        func int(_ k: String, _ def: Int) -> Int { d.object(forKey: k) as? Int ?? def }
        goLive(url: d.string(forKey: "rtmpURL") ?? "rtmps://fa723fc1b171.global-contribute.live-video.net:443/app/",
               key: d.string(forKey: "streamKey") ?? "", micUID: d.string(forKey: "micUID") ?? "",
               fallbackPosition: d.string(forKey: "fallbackCamera") == "front" ? .front : .back,
               bitrateKbps: int("bitrateKbps", 4000), codec: StreamViewModel().codec, srtLatencyMs: int("srtLatencyMs", 2000),
               quality: .init(height: int("phoneHeight", 720), landscape: d.bool(forKey: "phoneLandscape"), fps: int("phoneFps", 30),
                              stabilization: d.string(forKey: "phoneStabilization") ?? "off"))
    }
}
