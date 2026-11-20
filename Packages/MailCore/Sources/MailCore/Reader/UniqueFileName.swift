/// A file name that doesn't repeat one already in a folder, numbered as the Finder numbers copies.
public enum UniqueFileName {
    /// `filename`, or "name 2.ext", "name 3.ext" and on, the first `taken` doesn't say is in use.
    public static func choosing(_ filename: String, taken: (String) -> Bool) -> String {
        guard taken(filename) else { return filename }
        var stem = filename
        var suffix = ""
        // A leading dot makes a dotfile, not an extension.
        if let dot = filename.lastIndex(of: "."), dot != filename.startIndex {
            stem = String(filename[..<dot])
            suffix = String(filename[dot...])
        }
        var number = 2
        while taken("\(stem) \(number)\(suffix)") { number += 1 }
        return "\(stem) \(number)\(suffix)"
    }
}
