import Foundation

/// The names of the files a conversation is shared as: its subject without the characters a file name can't hold.
public enum ExportFilename {
    /// "Plan Thursday.pdf" for "Plan: Thursday", or the fallback's name for a subject with nothing left.
    public static func name(for subject: String, fallback: String, extension ext: String) -> String {
        stem(for: subject, fallback: fallback) + "." + ext
    }

    /// One name per file: "Plan.eml", "Plan 2.eml", "Plan 3.eml".
    public static func names(for subject: String, count: Int, fallback: String, extension ext: String) -> [String] {
        let stem = stem(for: subject, fallback: fallback)
        return (1...max(count, 1)).prefix(count).map { $0 == 1 ? "\(stem).\(ext)" : "\(stem) \($0).\(ext)" }
    }

    private static func stem(for subject: String, fallback: String) -> String {
        let cleaned = subject.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
        return cleaned.isEmpty ? fallback : String(cleaned.prefix(100))
    }
}
