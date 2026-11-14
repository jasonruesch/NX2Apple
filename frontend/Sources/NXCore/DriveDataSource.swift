import Foundation

/// A game's packed data in the drive folder, for a game whose packed data on this Mac is gone (moved to the drive, say). The
/// drive's folder for the game is then the data to send or copy: a copy to that same drive finds every file there already, so
/// only what the data lacks goes (the game's signed framework, shaders).
package enum DriveDataSource {
    /// `<driveFolder>/<title ID>` or `<driveFolder>/<name> (<title ID>)`, the two namings `DriveCopy` writes, that holds a
    /// `romfs.img`. With both, the one `named` chooses wins. nil when the drive folder is not there or holds no such folder.
    package static func folder(in driveFolder: String, titleID: String, named: Bool = false, fm: FileManager = .default) -> String? {
        let upper = titleID.uppercased()
        guard !driveFolder.isEmpty, !upper.isEmpty, let names = try? fm.contentsOfDirectory(atPath: driveFolder) else { return nil }
        let matches = names.filter { name in
            !name.hasPrefix(".") && (name.uppercased() == upper || name.uppercased().hasSuffix(" (\(upper))"))
                && fm.fileExists(atPath: driveFolder + "/" + name + "/romfs.img")
        }.sorted()
        let byTitleID = matches.first { $0.uppercased() == upper }
        let byName = matches.first { $0.uppercased() != upper }
        let chosen = named ? (byName ?? byTitleID) : (byTitleID ?? byName)
        return chosen.map { driveFolder + "/" + $0 }
    }
}
