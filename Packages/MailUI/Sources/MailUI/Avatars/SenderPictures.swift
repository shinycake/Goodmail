import MailCore
import Synchronization
public import UIKit

/// Senders' pictures for the mail screens, as the alerts show them: a person's photo or a company's logo, decoded
/// small, off the main actor, and kept in memory. Where they come from is the app's to say, so MailUI knows nothing
/// of Contacts, BIMI or caches on disk.
nonisolated public final class SenderPictures: Sendable {
    /// What is known about a sender's picture without waiting.
    enum Lookup {
        case picture(UIImage)
        /// Asked already, and there is none.
        case none
        /// Not asked yet: `picture(for:)` finds out.
        case unknown
    }

    /// Pictures are decoded at this many points square, the largest avatar the screens draw, at the screen's scale.
    static let side: CGFloat = 40

    /// What is kept for one sender.
    private enum Entry {
        /// Being loaded, by the one task every caller waits for.
        case loading(Task<UIImage?, Never>)
        /// Loaded: the picture, or `nil` for none.
        case known(UIImage?)
    }

    private struct State {
        var entries: [String: Entry] = [:]
        /// The known entries, oldest first, for evicting.
        var order: [String] = []
    }

    /// Enough for every sender in a long mailbox; a few megabytes at most.
    private static let capacity = 300

    private let load: @Sendable (String) async -> Data?
    private let scale: CGFloat
    private let state = Mutex(State())

    /// `load` gives the PNG or JPEG data of the picture for an address, or `nil` when there is none.
    public init(scale: CGFloat, load: @escaping @Sendable (String) async -> Data?) {
        self.scale = scale
        self.load = load
    }

    func lookup(for address: String) -> Lookup {
        guard let key = Self.key(for: address) else { return .none }
        return state.withLock { state in
            switch state.entries[key] {
            case .known(let image?): .picture(image)
            case .known(nil): .none
            case .loading, nil: .unknown
            }
        }
    }

    /// The sender's picture, loaded once however many rows ask for it at the same time.
    @concurrent func picture(for address: String) async -> UIImage? {
        switch entry(address) {
        case .known(let image): image
        case .loading(let task): await task.value
        }
    }

    /// Starts loading the pictures of senders whose rows are about to show, so they're known when the rows draw.
    /// Each load remembers its picture when it finishes, whether or not anyone waits for it.
    func warm(_ addresses: [String]) {
        for address in addresses { _ = entry(address) }
    }

    /// The picture if it's known, else the load under way for it, started now if there is none.
    private func entry(_ address: String) -> Entry {
        guard let key = Self.key(for: address) else { return .known(nil) }
        return state.withLock { state in
            if let entry = state.entries[key] { return entry }
            // It can't finish before it's recorded below: remembering takes the lock this holds.
            let started = Task { @concurrent [self] in
                let image = await load(address).flatMap { Self.decode($0, scale: scale) }
                remember(image, for: key)
                return image
            }
            let entry = Entry.loading(started)
            state.entries[key] = entry
            return entry
        }
    }

    private func remember(_ image: UIImage?, for key: String) {
        state.withLock { state in
            state.entries[key] = .known(image)
            state.order.append(key)
            if state.order.count > Self.capacity { state.entries[state.order.removeFirst()] = nil }
        }
    }

    /// One entry per address, however it's capitalized; `nil` for no address.
    private static func key(for address: String) -> String? {
        let key = address.trimmingCharacters(in: .whitespaces).lowercased()
        return key.isEmpty ? nil : key
    }

    private static func decode(_ data: Data, scale: CGFloat) -> UIImage? {
        let pixels = side * scale
        return UIImage(data: data)?.preparingThumbnail(of: CGSize(width: pixels, height: pixels))
    }
}

/// Where a window's views find its `SenderPictures`. The app sets it on each window; views without it show initials.
nonisolated struct SenderPicturesTrait: UITraitDefinition {
    static let defaultValue: SenderPictures? = nil
}

extension UIMutableTraits {
    public var senderPictures: SenderPictures? {
        get { self[SenderPicturesTrait.self] }
        set { self[SenderPicturesTrait.self] = newValue }
    }
}

extension UITraitCollection {
    var senderPictures: SenderPictures? { self[SenderPicturesTrait.self] }
}

/// Shows one sender's picture in an avatar view, following the views it's reused for: a row that moves on to another
/// thread drops the picture it was waiting for.
@MainActor final class SenderPictureBinding {
    /// What the avatar is bound to.
    private enum Bound {
        /// No address or no pictures: the initials.
        case none
        /// `address`'s picture from `pictures`, shown, or known to be none.
        case shown(address: String, pictures: SenderPictures)
        /// Waiting for `address`'s picture, with the initials meanwhile.
        case loading(address: String, pictures: SenderPictures, Task<Void, Never>)

        func isBound(to address: String?, in pictures: SenderPictures?) -> Bool {
            switch self {
            case .none: address == nil || pictures == nil
            case .shown(let bound, let source), .loading(let bound, let source, _):
                bound == address && source === pictures
            }
        }
    }

    private var bound = Bound.none

    deinit {
        if case .loading(_, _, let task) = bound { task.cancel() }
    }

    /// Shows `address`'s picture through `show`: at once when it's known, after loading when it isn't, and `nil`
    /// (the initials) meanwhile. A `nil` address or `pictures` shows initials.
    func bind(address: String?, pictures: SenderPictures?, show: @escaping @MainActor (UIImage?) -> Void) {
        guard !bound.isBound(to: address, in: pictures) else { return }
        if case .loading(_, _, let task) = bound { task.cancel() }
        guard let address, let pictures else {
            bound = .none
            return show(nil)
        }
        switch pictures.lookup(for: address) {
        case .picture(let image):
            bound = .shown(address: address, pictures: pictures)
            show(image)
        case .none:
            bound = .shown(address: address, pictures: pictures)
            show(nil)
        case .unknown:
            show(nil)
            let load = Task { [weak self] in
                let image = await pictures.picture(for: address)
                // Rebound meanwhile: the avatar shows another sender now.
                guard !Task.isCancelled, let self else { return }
                bound = .shown(address: address, pictures: pictures)
                show(image)
            }
            bound = .loading(address: address, pictures: pictures, load)
        }
    }
}
