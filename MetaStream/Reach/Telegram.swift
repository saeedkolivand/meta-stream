import Foundation

/// Minimal Telegram Bot API client for the Live post. Plain text only (no parse_mode, so nothing needs escaping).
/// The token lives in the Keychain ("telegramToken"), the channel in UserDefaults ("telegramChannel"). Errors never
/// carry the request URL, so the token cannot reach the log.
enum Telegram {
    struct Failure: LocalizedError, Sendable {
        let text: String
        var errorDescription: String? { text }
    }

    private static var token: String { KeychainTokenStore().string(forKey: "telegramToken") ?? "" }
    private static var channel: String {
        (UserDefaults.standard.string(forKey: "telegramChannel") ?? "").trimmingCharacters(in: .whitespaces)
    }

    // MARK: messages

    /// Posts `text` to the channel and returns its message id.
    static func sendMessage(text: String, replyTo: Int? = nil) async throws -> Int {
        var params: [String: any Sendable] = ["chat_id": channel, "text": String(text.prefix(4096))]
        if let replyTo {
            params["reply_parameters"] = ["message_id": replyTo, "allow_sending_without_reply": true] as [String: any Sendable]
        }
        return try messageId(await call("sendMessage", params))
    }

    static func editText(_ id: Int, text: String) async throws {
        _ = try await call("editMessageText", ["chat_id": channel, "message_id": id, "text": String(text.prefix(4096))])
    }

    static func editCaption(_ id: Int, caption: String) async throws {
        _ = try await call("editMessageCaption", ["chat_id": channel, "message_id": id, "caption": String(caption.prefix(1024))])
    }

    static func deleteMessage(_ id: Int) async throws {
        _ = try await call("deleteMessage", ["chat_id": channel, "message_id": id])
    }

    static func sendPhoto(jpeg: Data, caption: String) async throws -> Int {
        let (body, type) = multipart(["chat_id": channel, "caption": String(caption.prefix(1024))], file: jpeg, field: "photo")
        return try messageId(await send("sendPhoto", body: body, type: type))
    }

    /// Replaces the photo (or turns a text message into a photo) and sets its caption.
    static func editPhoto(_ id: Int, jpeg: Data, caption: String) async throws {
        let media = ["type": "photo", "media": "attach://frame", "caption": String(caption.prefix(1024))]
        let json = try String(data: JSONSerialization.data(withJSONObject: media), encoding: .utf8) ?? "{}"
        let (body, type) = multipart(["chat_id": channel, "message_id": "\(id)", "media": json], file: jpeg, field: "frame")
        _ = try await send("editMessageMedia", body: body, type: type)
    }

    /// The post was deleted by hand (or never existed): nothing left to edit or delete.
    static func isGone(_ error: Error) -> Bool {
        guard let text = (error as? Failure)?.text.lowercased() else { return false }
        return ["message to edit not found", "message to delete not found", "message_id_invalid"].contains { text.contains($0) }
    }

    // MARK: check

    /// What the bot can do in the channel, in words. Posts nothing.
    static func check() async -> String {
        guard !token.isEmpty else { return "No bot token saved" }
        guard !channel.isEmpty else { return "No channel set" }
        do {
            let me = try result(await call("getMe", [:]))
            let chat = try result(await call("getChat", ["chat_id": channel]))
            let name = "@\(me["username"] as? String ?? "bot")", title = chat["title"] as? String ?? channel
            guard let botId = me["id"] as? Int else { return "Telegram did not say who the bot is" }
            let member = try result(await call("getChatMember", ["chat_id": channel, "user_id": botId]))
            if member["status"] as? String == "creator" { return "\(name) can post, edit and delete in \(title)" }
            guard member["status"] as? String == "administrator" else { return "\(name) is not an admin of \(title)" }
            let missing = [("can_post_messages", "post"), ("can_edit_messages", "edit"), ("can_delete_messages", "delete")]
                .filter { member[$0.0] as? Bool != true }.map { $0.1 }
            return missing.isEmpty ? "\(name) can post, edit and delete in \(title)"
                : "\(name) cannot \(missing.joined(separator: ", ")) in \(title): grant it in the channel's admin settings"
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: transport

    private static func call(_ method: String, _ params: [String: any Sendable]) async throws -> Data {
        try await send(method, body: JSONSerialization.data(withJSONObject: params), type: "application/json")
    }

    /// POSTs and returns the response once Telegram says ok. "message is not modified" counts as ok; a 429 throws
    /// (callers just try again on their next tick).
    private static func send(_ method: String, body: Data, type: String) async throws -> Data {
        guard !token.isEmpty, let url = URL(string: "https://api.telegram.org/bot\(token)/\(method)") else {
            throw Failure(text: "no bot token")
        }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue(type, forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let data: Data
        do {
            data = try await URLSession.shared.data(for: req).0
        } catch {
            // the code only, never the error itself: its text can hold the URL
            throw Failure(text: "network error \((error as? URLError)?.code.rawValue ?? 0)")
        }
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if obj?["ok"] as? Bool == true { return data }
        let desc = obj?["description"] as? String ?? "unreadable reply"
        if desc.contains("message is not modified") { return data }
        throw Failure(text: desc)
    }

    private static func result(_ data: Data) throws -> [String: Any] {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let found = obj["result"] as? [String: Any] else {
            throw Failure(text: "unexpected reply")
        }
        return found
    }

    private static func messageId(_ data: Data) throws -> Int {
        guard let id = try result(data)["message_id"] as? Int else { throw Failure(text: "no message id in reply") }
        return id
    }

    /// multipart/form-data with text fields and one JPEG part named `field`.
    private static func multipart(_ fields: [String: String], file: Data, field: String) -> (Data, String) {
        let boundary = "ms-" + UUID().uuidString
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        let head = "Content-Disposition: form-data; name=\"\(field)\"; filename=\"frame.jpg\"\r\nContent-Type: image/jpeg"
        body.append(Data("--\(boundary)\r\n\(head)\r\n\r\n".utf8))
        body.append(file)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return (body, "multipart/form-data; boundary=\(boundary)")
    }
}
