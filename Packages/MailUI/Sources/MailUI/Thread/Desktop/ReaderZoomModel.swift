import Foundation
import MailCore
import Observation

/// How large this device's reader shows messages. One of the device's own choices, kept in `UserDefaults` and left out
/// of `Preferences.syncedSettings` (ADR-024): a Mac display and a phone want different sizes. Every message view reads
/// it through Observation, so a change shows in each open window at once.
@MainActor
@Observable
final class ReaderZoomModel {
    static let shared = ReaderZoomModel()
    static let key = "readerZoom"

    private(set) var zoom: ReaderZoom
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        zoom = ReaderZoom(stored: defaults.object(forKey: Self.key) as? Double)
    }

    func zoomIn() { set(zoom.zoomedIn()) }
    func zoomOut() { set(zoom.zoomedOut()) }
    func reset() { set(.standard) }

    private func set(_ new: ReaderZoom) {
        guard new != zoom else { return }
        zoom = new
        defaults.set(new.factor, forKey: Self.key)
    }
}
