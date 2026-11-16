import CoreGraphics
import Testing
import UIKit

@testable import MailUI

@Suite("Mail columns")
struct MailColumnsTests {
    @Test(
        "The list stays beside the thread, and the mailboxes join them only when the thread keeps its width",
        arguments: [
            // iPhone Duo's inner display, portrait and landscape.
            (CGFloat(669), UISplitViewController.DisplayMode.oneBesideSecondary),
            (951, .oneBesideSecondary),
            // iPad mini, portrait and landscape.
            (744, .oneBesideSecondary),
            (1133, .twoBesideSecondary),
            (MailColumns.threeColumnWidth, .twoBesideSecondary),
        ])
    func displayMode(width: CGFloat, mode: UISplitViewController.DisplayMode) {
        #expect(MailColumns.displayMode(forWidth: width) == mode)
    }
}
