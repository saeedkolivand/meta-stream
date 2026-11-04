import Chat
import CoreLogging
import SwiftUI

/// The in-app Logs screen (Settings > Diagnostics), plus the chat flood test.
struct LogView: View {
    private let store = LogStore.shared
    @Environment(ChatFeed.self) var chat
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(store.text.isEmpty ? "No log lines yet." : store.text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .id("end")
            }
            .onChange(of: store.text) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { ShareLink(item: store.text) { Image(systemName: "square.and.arrow.up") } }
            ToolbarItem(placement: .cancellationAction) { Button("Clear") { store.clear() } }
            ToolbarItem(placement: .bottomBar) {
                Button(chat.flooding ? "Stop chat flood" : "Chat flood test") { chat.toggleFlood() }
            }
        }
    }
}
