import Testing

@testable import MailUI

@MainActor
struct AttachmentSourceTests {
    @Test func offersEverythingOnADeviceWithACameraAndScanner() {
        let sources = AttachmentSource.available(on: .init(hasCamera: true, canScan: true))
        #expect(sources == [.photoLibrary, .file, .camera, .scan])
    }

    @Test func hidesTheCameraWhenThereIsNone() {
        let sources = AttachmentSource.available(on: .init(hasCamera: false, canScan: true))
        #expect(sources == [.photoLibrary, .file, .scan])
    }

    @Test func hidesScanningWhenTheDeviceCannot() {
        let sources = AttachmentSource.available(on: .init(hasCamera: true, canScan: false))
        #expect(sources == [.photoLibrary, .file, .camera])
    }

    @Test func keepsPhotosAndFilesWithoutHardware() {
        let sources = AttachmentSource.available(on: .init(hasCamera: false, canScan: false))
        #expect(sources == [.photoLibrary, .file])
    }

    /// Simulators differ in what they report, so this holds the menu to whatever this one says it has.
    @Test func theMenuFollowsWhatThisDeviceReports() {
        let hardware = AttachmentSource.Hardware.current
        let sources = AttachmentSource.available(on: hardware)
        #expect(sources.prefix(2) == [.photoLibrary, .file])
        #expect(sources.contains(.camera) == hardware.hasCamera)
        #expect(sources.contains(.scan) == hardware.canScan)
    }
}
