import UIKit

/// How big a viewer window is on the Mac: a new one opens wide enough for the sidebar, the list and a letter side by
/// side, and none shrinks below room for the list beside a letter. One the system restores keeps the frame the reader
/// left it at. An iPhone or iPad scene has no say over its size.
enum ViewerWindowSize {
    static let opening = CGSize(width: 1280, height: 800)
    static let minimum = CGSize(width: 720, height: 480)

    static func fit(_ scene: UIWindowScene, isNew: Bool) {
        guard scene.traitCollection.userInterfaceIdiom == .mac else { return }
        scene.sizeRestrictions?.minimumSize = minimum
        #if targetEnvironment(macCatalyst)
            guard isNew else { return }
            // Grown about the middle of where the system placed it; macOS keeps it on the screen.
            let placed = scene.effectiveGeometry.systemFrame
            let frame = CGRect(
                x: placed.midX - opening.width / 2, y: placed.midY - opening.height / 2, width: opening.width,
                height: opening.height)
            scene.requestGeometryUpdate(.Mac(systemFrame: frame))
        #endif
    }
}
