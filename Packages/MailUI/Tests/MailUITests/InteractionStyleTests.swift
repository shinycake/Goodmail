import Testing
import UIKit

@testable import MailUI

@MainActor
@Suite struct InteractionStyleTests {
    @Test(arguments: [
        (UIUserInterfaceIdiom.mac, InteractionStyle.desktop),
        (.pad, .touch),
        (.phone, .touch),
    ])
    func `only the Mac idiom is driven as a desktop`(idiom: UIUserInterfaceIdiom, style: InteractionStyle) {
        #expect(InteractionStyle(idiom: idiom) == style)
    }

    @Test(arguments: [
        (UIUserInterfaceIdiom.mac, true),
        (.pad, true),
        (.phone, false),
    ])
    func `the menu bar is on the Mac and iPad`(idiom: UIUserInterfaceIdiom, shown: Bool) {
        #expect(InteractionStyle.showsMenuBar(idiom: idiom) == shown)
    }

    @Test func `a window's trait is touch until the app sets it`() {
        let window = UIView()
        let screen = UIView()
        window.addSubview(screen)
        #expect(screen.traitCollection.interactionStyle == .touch)
        window.traitOverrides.interactionStyle = .desktop
        // An override reaches the trait collections at the next trait update, which UIKit makes when views are shown.
        window.updateTraitsIfNeeded()
        screen.updateTraitsIfNeeded()
        #expect(screen.traitCollection.interactionStyle == .desktop)
    }
}
