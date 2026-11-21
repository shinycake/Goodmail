import MailCore
import Testing
import UIKit

@testable import MailUI

/// Format > Font gives ⌘+ and ⌘- to Zoom In and Zoom Out, as in Apple Mail, and keeps its other keys.
@Suite("Font menu keys")
@MainActor
struct MailMenusFontTests {
    private let font = UIMenu(
        title: "Font",
        children: [
            UIKeyCommand(
                title: "Bold", action: #selector(UIResponder.toggleBoldface(_:)), input: "b", modifierFlags: .command),
            UIMenu(
                options: .displayInline,
                children: [
                    UIKeyCommand(
                        title: "Bigger", action: #selector(UIResponder.increaseSize(_:)), input: "+",
                        modifierFlags: .command),
                    UIKeyCommand(
                        title: "Smaller", action: #selector(UIResponder.decreaseSize(_:)), input: "-",
                        modifierFlags: .command),
                ]),
        ])

    @Test("Bigger and Smaller stay, doing what they did, without keys")
    func sizesLoseTheirKeys() throws {
        let sizes = try #require(MailMenus.withoutSizeKeys(font.children).last as? UIMenu).children
        #expect(sizes.map { ($0 as? UICommand)?.title } == ["Bigger", "Smaller"])
        #expect(sizes.allSatisfy { !($0 is UIKeyCommand) })
        #expect(
            sizes.compactMap { ($0 as? UICommand)?.action }
                == [#selector(UIResponder.increaseSize(_:)), #selector(UIResponder.decreaseSize(_:))])
    }

    @Test("The rest of the menu keeps its keys")
    func othersKeepTheirKeys() {
        let bold = MailMenus.withoutSizeKeys(font.children).first as? UIKeyCommand
        #expect(bold?.input == "b")
    }

    @Test("Zoom In and Zoom Out hold the keys Bigger and Smaller gave up")
    func zoomTakesTheKeys() {
        #expect(MailCommand.zoomIn.keys.chord == KeyChord(.command, "+"))
        #expect(MailCommand.zoomOut.keys.chord == KeyChord(.command, "-"))
    }
}
