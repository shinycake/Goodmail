import Foundation
import MailCore
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import MailUI

/// Every file the picker takes, picked in Files or captured, goes through one queue that its place finishing stops:
/// none lands in a message that has gone, as a reader left or a composer that sent.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AttachmentPickerTests {
    /// The files that landed.
    @MainActor
    final class Landed {
        var names: [String] = []
    }

    private func file(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(name)")
        try Data([1, 2, 3]).write(to: url)
        return url
    }

    private static func descendants(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap(descendants(of:))
    }

    private func pick(_ urls: [URL], in picker: AttachmentPicker) {
        picker.documentPicker(UIDocumentPickerViewController(forOpeningContentTypes: [.item]), didPickDocumentsAt: urls)
    }

    @Test func filesAndCapturesLandInTheOrderChosen() async throws {
        let landed = Landed()
        let picker = AttachmentPicker { landed.names.append($0.filename) }
        let notes = try file("notes.txt")
        pick([notes], in: picker)
        picker.attach { DraftAttachment(filename: "scan.pdf", mimeType: "application/pdf", data: Data([1])) }
        while landed.names.count < 2 { await Task.yield() }
        #expect(landed.names == [notes.lastPathComponent, "scan.pdf"])
    }

    /// A capture that waits until the test opens it, and says when it has started.
    private struct HeldCapture {
        let started: AsyncStream<Void>
        let open: AsyncStream<Void>.Continuation
        let prepare: CapturedAttachment.Preparation

        init(named name: String) {
            let (started, starting) = AsyncStream.makeStream(of: Void.self)
            let (gate, open) = AsyncStream.makeStream(of: Void.self)
            self.started = started
            self.open = open
            prepare = {
                starting.yield()
                for await _ in gate { break }
                return DraftAttachment(filename: name, mimeType: "application/pdf", data: Data([1]))
            }
        }

        func waitUntilStarted() async {
            for await _ in started { break }
        }
    }

    @Test func aFilePreparedAsThePlaceFinishesNeverLands() async {
        let landed = Landed()
        let picker = AttachmentPicker { landed.names.append($0.filename) }
        let capture = HeldCapture(named: "scan.pdf")
        picker.attach(capture.prepare)
        await capture.waitUntilStarted()
        picker.finish()
        capture.open.yield()
        for _ in 0..<50 { await Task.yield() }
        #expect(landed.names.isEmpty)
    }

    /// A capture that fails says so, and the ones chosen after it still land.
    @Test func aFailedCaptureLeavesTheQueueGoing() async {
        struct Broken: Error {}
        let landed = Landed()
        let picker = AttachmentPicker { landed.names.append($0.filename) }
        picker.attach { throw Broken() }
        picker.attach { throw CancellationError() }
        picker.attach { DraftAttachment(filename: "after.pdf", mimeType: "application/pdf", data: Data([1])) }
        while landed.names.isEmpty { await Task.yield() }
        #expect(landed.names == ["after.pdf"])
    }

    /// Files a chat reply was still preparing as it went stay out of the next reply.
    @Test func aChatReplySentDropsWhatItWasStillPreparing() async throws {
        let bar = ChatComposerBar()
        var sent: [[DraftAttachment]] = []
        bar.onSend = { _, attachments, _ in sent.append(attachments) }
        let capture = HeldCapture(named: "late.pdf")
        bar.picker.attach(capture.prepare)
        await capture.waitUntilStarted()
        let textView = try #require(Self.descendants(of: bar).compactMap { $0 as? UITextView }.first)
        textView.text = "On my way"
        bar.textViewDidChange(textView)
        bar.send()
        capture.open.yield()
        for _ in 0..<50 { await Task.yield() }
        #expect(sent.map(\.count) == [0])
        #expect(bar.unsent == nil, "nothing landed in the emptied field")
    }

    /// A sheet still up keeps its picker, finished and let go by its place, so its buttons can still dismiss it.
    @Test func aSheetKeepsThePickerThatPresentedIt() {
        let sheet = UIViewController()
        weak var kept: AttachmentPicker?
        do {
            let picker = AttachmentPicker { _ in }
            kept = picker
            picker.present(sheet)
            picker.finish()
        }
        #expect(kept != nil)
        withExtendedLifetime(sheet) {}
    }

    @Test func filesPickedAsThePlaceFinishesNeverLand() async throws {
        let landed = Landed()
        let picker = AttachmentPicker { landed.names.append($0.filename) }
        pick([try file("a.txt"), try file("b.txt")], in: picker)
        picker.attach { DraftAttachment(filename: "scan.pdf", mimeType: "application/pdf", data: Data([1])) }
        picker.finish()
        pick([try file("late.txt")], in: picker)
        for _ in 0..<50 { await Task.yield() }
        #expect(landed.names.isEmpty)
    }
}
