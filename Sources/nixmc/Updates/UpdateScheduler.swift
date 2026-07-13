import CoreGraphics
import Foundation

/// Opportunistic trigger for the update check. The scheduler ticks every
/// ~30 minutes (poll-short); the user-configured cadence and idle gate
/// (`AppSettings`) are checked against the persisted `lastChecked` by the
/// caller's `shouldRun` (gate-long). Never set the activity interval to the
/// cadence itself — it counts from `schedule()`, so a relaunch would reset
/// the clock and a catch-up would never fire.
@MainActor
final class UpdateScheduler {
    static let identifier = "app.nixmc.update-check" // literal; Bundle id may be nil (SwiftPM exe)
    static let pollInterval: TimeInterval = 30 * 60

    private var activity: NSBackgroundActivityScheduler?

    func start(shouldRun: @escaping @MainActor () -> Bool,
               fire: @escaping @MainActor () async -> Void) {
        stop()
        let activity = NSBackgroundActivityScheduler(identifier: Self.identifier)
        activity.repeats = true
        activity.interval = Self.pollInterval
        activity.tolerance = Self.pollInterval / 2
        activity.qualityOfService = .utility
        activity.schedule { completion in
            // The block arrives on the scheduler's internal queue.
            Task { @MainActor in
                if shouldRun() {
                    await fire()
                    completion(.finished)
                } else {
                    completion(.deferred)
                }
            }
        }
        self.activity = activity
    }

    func stop() {
        activity?.invalidate()
        activity = nil
    }

    /// Seconds since the user last touched mouse or keyboard. The classic
    /// kCGAnyInputEventType (~0) imports as nil in Swift, so take the minimum
    /// across the concrete event types instead.
    static func secondsSinceLastUserInput() -> TimeInterval {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown,
                                    .otherMouseDown, .keyDown, .scrollWheel]
        return types.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }.min() ?? 0
    }
}
