import MailCore
import SwiftUI
import Testing

@testable import MailUI

@MainActor @Suite struct SettingsPagesTests {
    @Test func `Settings opens at the page asked for`() {
        #expect(SettingsPages().path.isEmpty)
        #expect(SettingsPages(at: .swipeActions).path.count == 1)
    }

    @Test func `a page asked for while Settings is open shows once, over the first screen`() {
        let pages = SettingsPages()
        pages.path.append(AccountID(rawValue: "a"))
        pages.show(.swipeActions)
        #expect(pages.path.count == 1, "in place of the account the reader had open")
        pages.show(.swipeActions)
        #expect(pages.path.count == 1, "asked twice, shown once")
    }

    @Test func `asking for the first screen leaves the reader where they are`() {
        let pages = SettingsPages(at: .swipeActions)
        pages.show(.main)
        #expect(pages.path.count == 1)
    }
}
