// Live data the widgets read each tick. Weak so a widget task never keeps the app's models alive.
import Foundation

/// Set once by ContentView; nil until then (widgets render nothing / blank values).
@MainActor
final class WidgetContext {
    weak var chat: ChatFeed?
    weak var emotes: Emotes?
    weak var streamer: Streamer?
    weak var platforms: Platforms?
}
