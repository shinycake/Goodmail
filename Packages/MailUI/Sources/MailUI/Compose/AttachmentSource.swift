import UIKit
import VisionKit

/// Where a file can be taken from when attaching to a message.
enum AttachmentSource: CaseIterable {
    case photoLibrary
    case file
    case camera
    case scan

    /// What the device can do. A simulator may report a camera and scanner as well.
    struct Hardware: Equatable {
        var hasCamera: Bool
        var canScan: Bool

        static var current: Hardware {
            Hardware(
                hasCamera: UIImagePickerController.isSourceTypeAvailable(.camera),
                canScan: VNDocumentCameraViewController.isSupported)
        }
    }

    /// The sources worth showing in the attach menu, in menu order.
    static func available(on hardware: Hardware) -> [AttachmentSource] {
        allCases.filter {
            switch $0 {
            case .photoLibrary, .file: true
            case .camera: hardware.hasCamera
            case .scan: hardware.canScan
            }
        }
    }
}
