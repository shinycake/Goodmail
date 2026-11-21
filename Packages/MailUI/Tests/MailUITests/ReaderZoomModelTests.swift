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
        // The lists sync their own items, whatever their key; the defaults that sync are the values named here.
        let values = Preferences.syncedSettings.compactMap { $0 as? DefaultsValues }
        #expect(try values.allSatisfy { try !$0.local().scope.covers(ReaderZoomModel.key) })
    }
}
