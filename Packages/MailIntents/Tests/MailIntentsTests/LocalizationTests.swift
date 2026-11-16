import Foundation
import Testing

/// Every string Shortcuts shows for Goodmail's actions has a Hebrew translation in the app's catalog for its table.
struct LocalizationTests {
    private static let sources = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../Sources/MailIntents").standardized
    private static let app = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../../Goodmail").standardized

    /// Each `table:` string in the sources, keyed as the catalog keys it: `${name}` for a summary's parameter and
    /// `%@` for an interpolated value.
    private static func keys() throws -> [(table: String, key: String)] {
        let files =
            FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        let literal = /(?:LocalizedStringResource|Summary)\(\s*"((?:[^"\\]|\\.)*)",\s*table: "(\w+)"/
        return try files.flatMap { file in
            try String(contentsOf: file, encoding: .utf8).matches(of: literal).map { match in
                let key = String(match.1)
                    .replacing(/\\\(\\\.\$(\w+)\)/) { "${\($0.1)}" }
                    .replacing(/\\\(\w+\)/, with: "%@")
                return (String(match.2), key)
            }
        }
    }

    @Test func everyShortcutsStringHasHebrew() throws {
        let keys = try Self.keys()
        #expect(keys.count > 100, "the sources are where the test expects them")
        var catalogs: [String: [String: Any]] = [:]
        for table in Set(keys.map(\.table)) {
            let data = try Data(contentsOf: Self.app.appending(path: "\(table).xcstrings"))
            let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            catalogs[table] = try #require(json["strings"] as? [String: Any])
        }
        let untranslated = keys.filter { table, key in
            let entry = catalogs[table]?[key] as? [String: Any]
            let hebrew = (entry?["localizations"] as? [String: Any])?["he"] as? [String: Any]
            return ((hebrew?["stringUnit"] as? [String: Any])?["value"] as? String)?.isEmpty ?? true
        }
        #expect(untranslated.isEmpty, "untranslated: \(untranslated.map { "\($0.table): \($0.key)" })")
    }
}
