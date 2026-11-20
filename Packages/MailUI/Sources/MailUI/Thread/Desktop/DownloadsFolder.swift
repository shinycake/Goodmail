import Foundation
import MailCore

/// Copies a downloaded attachment into the Downloads folder, which a Mac app reaches with the user-selected
/// Downloads entitlement (`com.apple.security.files.downloads.read-write`) once it is sandboxed.
nonisolated enum DownloadsFolder {
    /// The file's copy in Downloads, named as the file is or numbered when that name is taken. The copy runs off the
    /// main actor, as any file work does.
    @concurrent
    static func save(_ file: URL) async throws -> URL {
        let fileManager = FileManager.default
        let folder = try fileManager.url(
            for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        // Another process may take the name between the check and the copy, so a refused copy asks for the next one.
        var refused: Set<String> = []
        while true {
            try Task.checkCancellation()
            let name = UniqueFileName.choosing(file.lastPathComponent) {
                refused.contains($0) || fileManager.fileExists(atPath: folder.appending(path: $0).path)
            }
            let copy = folder.appending(path: name)
            do {
                try fileManager.copyItem(at: file, to: copy)
                return copy
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                refused.insert(name)
            }
        }
    }
}

/// The saves in flight, one per attachment, owned by the conversation that started them and cancelled with it.
@MainActor
final class DownloadsSaver {
    private var saves: [String: Task<Void, Never>] = [:]

    deinit {
        for save in saves.values { save.cancel() }
    }

    /// Fetches the attachment's file with `file`, copies it to Downloads, and reports where it went or why it
    /// couldn't. `loading` shows the wait on the attachment.
    func save(
        _ attachment: Attachment, file: @escaping () async throws -> URL, loading: @escaping (Bool) -> Void,
        finished: @escaping (Result<URL, any Error>) -> Void
    ) {
        guard saves[attachment.id] == nil else { return }
        loading(true)
        saves[attachment.id] = Task { [weak self] in
            let result: Result<URL, any Error>
            do {
                result = .success(try await DownloadsFolder.save(try await file()))
            } catch is CancellationError {
                loading(false)
                return
            } catch {
                result = .failure(error)
            }
            loading(false)
            self?.saves[attachment.id] = nil
            finished(result)
        }
    }
}
