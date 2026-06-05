import Foundation
import Combine

/// Shared scroll position between the editor and the preview while split mode
/// is active. Each pane both reports its own scroll (as a 0…1 fraction of the
/// scrollable range) and observes the other pane's reports. The `source` tag
/// lets each side recognize and skip its own echo, so applying an incoming
/// update doesn't trigger an infinite loop.
final class ScrollSync: ObservableObject {
    enum Source { case editor, preview }

    struct Event: Equatable {
        let fraction: CGFloat
        let source: Source
    }

    @Published private(set) var event: Event = Event(fraction: 0, source: .editor)

    /// Publish a new fraction. Coalesces near-duplicates so a programmatically
    /// applied scroll doesn't ping-pong via floating-point drift.
    func report(_ fraction: CGFloat, from source: Source) {
        let clamped = max(0, min(1, fraction))
        if abs(clamped - event.fraction) < 0.0005 && event.source == source { return }
        event = Event(fraction: clamped, source: source)
    }
}
