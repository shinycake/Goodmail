import Testing
import UIKit

@testable import MailUI

@MainActor
@Suite("Select item")
struct SelectItemTests {
    @Test("A checklist that still reads Select")
    func readsSelect() {
        let select = SelectItem {}
        #expect(select.item.image == UIImage(systemName: "checklist"))
        #expect(select.item.title == "Select")
        #expect(select.item.accessibilityLabel == "Select")
    }

    @Test("Hidden until the list has threads")
    func startsHidden() {
        #expect(SelectItem {}.item.isHidden)
    }

    @Test("Shows while there are threads, hides once there are none")
    func followsTheRows() {
        let select = SelectItem {}
        select.show(rows: 3)
        #expect(!select.item.isHidden)
        select.show(rows: 1)
        #expect(!select.item.isHidden)
        select.show(rows: 0)
        #expect(select.item.isHidden)
    }

    @Test("Tapping it starts selecting")
    func tapBegins() throws {
        var began = 0
        let select = SelectItem { began += 1 }
        let action = try #require(select.item.primaryAction)
        action.performWithSender(nil, target: nil)
        #expect(began == 1)
    }
}
