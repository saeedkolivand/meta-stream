// Live data the widgets read each tick. Weak so a widget task never keeps the app's models alive.
import Chat
import Engine
import Foundation
import Platforms

/// Set once by ContentView; nil until then (widgets render nothing / blank values).
@MainActor
public final class WidgetContext {
    public weak var chat: ChatFeed?
    public weak var emotes: Emotes?
    public weak var streamer: Streamer?
    public weak var platforms: Platforms?
}
