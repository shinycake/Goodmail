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

    #if targetEnvironment(simulator)
        @Test func theSimulatorOffersNeitherCameraNorScanner() {
            #expect(AttachmentSource.available(on: .current) == [.photoLibrary, .file])
        }
    #endif
}
