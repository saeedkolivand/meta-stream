// Watching an @Observable value from outside SwiftUI (the Combine `$value.dropFirst().removeDuplicates().sink`
// replacement): `Observations` yields the current value, then each settled change.
import Observation

/// Calls `changed` with each new value of `value` after the current one; equal repeats are skipped. Cancel the
/// returned task to stop.
@MainActor @discardableResult
public func watch<T: Equatable & Sendable>(_ value: @escaping @MainActor @Sendable () -> T,
                                           _ changed: @escaping @MainActor @Sendable (T) -> Void) -> Task<Void, Never> {
    Task { @MainActor in
        var last: T?
        for await v in Observations(value) {
            if let last, last != v { changed(v) }
            last = v
        }
    }
}
