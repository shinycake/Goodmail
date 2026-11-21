import SwiftUI
import Testing
import UIKit

@testable import MailUI

/// An arrival from outside clears the sheets that only read or pick, and leaves everything up while an alert, a
/// sign-in, a transfer or the accounts offer is among them (R3).
@MainActor
struct UncoverTests {
    @Test func anAlertOnTopBlocks() {
        let alert = UIAlertController(title: "Delete Forever?", message: nil, preferredStyle: .alert)
        #expect(Uncovering.blocks([UINavigationController(), alert]), "the alert's sheet stays with it")
        #expect(Uncovering.blocks([alert]))
    }

    @Test func aPickerDoesnt() {
        let picker = UINavigationController(rootViewController: UIViewController())
        #expect(!Uncovering.blocks([picker]))
        #expect(!Uncovering.blocks([UIActivityViewController(activityItems: ["x"], applicationActivities: nil)]))
        #expect(!Uncovering.blocks([]))
    }

    @Test func aSignInOrTransferBlocks() {
        let signIn = ICloudSignInScreen.make(signIn: { _, _ in }, finished: { _ in })
        #expect(Uncovering.blocks([UINavigationController(), signIn]))
        #expect(Uncovering.blocks([ArrivalBlockingHost(rootView: Text(verbatim: "Transfer"))]))
    }
}
