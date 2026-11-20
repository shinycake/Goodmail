import Foundation
import MailCore
import Testing

@testable import MailUI

/// The reader's zoom is this device's own choice (ADR-024).
@MainActor
struct ReaderZoomModelTests {
    private func defaults() throws -> UserDefaults {
        let name = "ReaderZoomModelTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func startsAtTheStandardSize() throws {
        #expect(ReaderZoomModel(defaults: try defaults()).zoom == .standard)
    }

    @Test func aChosenSizeIsKeptForTheNextLaunch() throws {
        let defaults = try defaults()
        let model = ReaderZoomModel(defaults: defaults)
        model.zoomIn()
        model.zoomIn()
        #expect(ReaderZoomModel(defaults: defaults).zoom == model.zoom)
        model.reset()
        #expect(ReaderZoomModel(defaults: defaults).zoom == .standard)
    }

    @Test func theSizeStaysOnTheDevice() throws {
        let keys = try Preferences.syncedSettings.flatMap { family -> [String] in
            let scope = try family.local().scope
            return [ReaderZoomModel.key].filter { scope.covers($0) }
        }
        #expect(keys.isEmpty)
    }
}
