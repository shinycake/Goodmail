import Testing
import UIKit

@testable import MailUI

/// An arrival from outside clears Settings and the sheets that only read or pick, and leaves everything up while
/// anything else is among them: an alert, a sign-in, a transfer, the accounts offer, or a screen nobody marked (R3).
@MainActor
struct UncoverTests {
    @Test func anAlertOnTopBlocks() {
        let alert = UIAlertController(title: "Delete Forever?", message: nil, preferredStyle: .alert)
        let picker = UINavigationController(
            rootViewController: LaterPickerViewController(title: "Snooze", actionTitle: "Snooze", initial: nil) { _ in }
        )
        #expect(!ArrivalCover.dismissible([picker, alert]), "the picker stays with the alert over it")
        #expect(!ArrivalCover.dismissible([alert]))
    }

    @Test func aPickerDoesnt() {
        let picker = UINavigationController(
            rootViewController: LaterPickerViewController(title: "Snooze", actionTitle: "Snooze", initial: nil) { _ in }
        )
        #expect(ArrivalCover.dismissible([picker]))
        #expect(ArrivalCover.dismissible([UIActivityViewController(activityItems: ["x"], applicationActivities: nil)]))
        #expect(ArrivalCover.dismissible([]))
    }

    @Test func aTransferOrTheAccountsOfferBlocks() {
        let sending = TransferSending(accounts: [], unlock: { true }, host: { fatalError("not hosted") })
        #expect(!ArrivalCover.dismissible([TransferSendScreen.make(model: sending)]))
        let offer = SharedAccountsOffer(accounts: [], add: { _, _ in }, decline: { _ in })
        #expect(!ArrivalCover.dismissible([SharedAccountsOfferScreen.make(offer: offer)]))
    }

    @Test func aScreenNobodyMarkedBlocks() {
        #expect(!ArrivalCover.dismissible([UINavigationController(rootViewController: UIViewController())]))
        #expect(!ArrivalCover.dismissible([UIViewController()]))
    }
}
