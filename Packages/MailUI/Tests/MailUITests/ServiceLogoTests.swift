import MailCore
import Testing
import UIKit

@testable import MailUI

/// Each brand service shows its own logo from the module's resources; any other server a neutral symbol.
@MainActor
struct ServiceLogoTests {
    @Test(arguments: [MailService.gmail, .outlook, .icloud])
    func aBrandShowsItsOwnLogo(_ service: MailService) throws {
        guard case .logo(let name) = service.mark else {
            Issue.record("\(service) has no logo")
            return
        }
        let image = try #require(ServiceLogoImages.image(named: name), "\(name).pdf is missing")
        #expect(image.size.width == image.size.height, "a logo fills a square icon slot")
        #expect(try #require(service.markImage).renderingMode == .alwaysOriginal, "a tint never recolors a logo")
    }

    /// Google's file carries its own margin and the Gmail and iCloud marks are wide, so drawing each artboard as it
    /// is made them look a quarter smaller than Outlook's beside them.
    @Test(arguments: ["GmailLogo", "OutlookLogo", "ICloudLogo"])
    func aLogosArtworkNotItsArtboardFillsTheSquare(_ name: String) throws {
        let page = try #require(ServiceLogoImages.page(named: name))
        let box = page.getBoxRect(.mediaBox)
        let ink = try #require(ServiceLogoImages.inkedBounds(of: page))
        #expect(box.contains(ink))
        #expect(ink.width > 0.5 * box.width && ink.height > 0.3 * box.height, "the artwork is found, not a speck")
    }

    @Test func anyOtherServerShowsANeutralSymbol() {
        #expect(MailService.imap.mark == .symbol("at"))
        #expect(MailService.imap.markImage != nil)
    }
}
