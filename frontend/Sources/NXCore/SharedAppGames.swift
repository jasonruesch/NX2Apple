import Foundation

/// The player's choices about the shared app's games, kept beside shell.json and out of it, so the library stays as upstream writes it:
/// - Excluded games stay built and in shell.json, but the IPA export leaves them out until they are included again. The install on a
///   device keeps every game. The list is `<shell root>/export-excluded.json`, title IDs in upper case.
/// - Removing a game takes it out of shell.json and discards its mirrored framework, so neither the export nor the install holds it
///   until the game is built again. The game's own build folder and its game data are not touched.
package enum SharedAppGames {
    package static func exclusionsFile(root: String) -> String { root + "/export-excluded.json" }

    /// The title IDs the export leaves out, upper case.
    package static func excluded(root: String, fm: FileManager = .default) -> Set<String> {
        guard let data = fm.contents(atPath: exclusionsFile(root: root)),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids.map { $0.uppercased() })
    }

    package static func isExcluded(_ titleID: String, root: String) -> Bool { excluded(root: root).contains(titleID.uppercased()) }

    /// Excludes a game from the export, or includes it again. An empty list removes the file.
    package static func setExcluded(_ titleID: String, _ excluded: Bool, root: String, fm: FileManager = .default) throws {
        var ids = self.excluded(root: root, fm: fm)
        if excluded { ids.insert(titleID.uppercased()) } else { ids.remove(titleID.uppercased()) }
        let file = exclusionsFile(root: root)
        if ids.isEmpty {
            if fm.fileExists(atPath: file) { try fm.removeItem(atPath: file) }
            return
        }
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(ids.sorted()).write(to: URL(fileURLWithPath: file), options: .atomic)
    }

    /// The library without the excluded games: what the export builds and packs. `keeping` is the game the export was handed (the one
    /// "Build and export" just built), which is never left out.
    package static func forExport(_ library: ShellLibrary, leavingOut ids: Set<String>, keeping titleID: String) -> ShellLibrary {
        var exported = library
        exported.games.removeAll { ids.contains($0.titleID.uppercased()) && $0.titleID.uppercased() != titleID.uppercased() }
        return exported
    }

    /// Takes the game out of the shared app: out of shell.json and the exclusions, and its framework discarded when it is the shell's own
    /// mirror (`<root>/frameworks/…`). A framework elsewhere (a build folder) is the build's and stays. The apps Xcode built drop its
    /// embedded copy the next time the shared app is installed or exported (`pruneEmbeddedFrameworks`). Returns whether the game was there.
    @discardableResult
    package static func remove(_ titleID: String, root: String, fm: FileManager = .default) throws -> Bool {
        var library = ShellLibrary.load(root: root)
        let id = titleID.uppercased()
        let gone = library.games.filter { $0.titleID.uppercased() == id }
        try setExcluded(titleID, false, root: root, fm: fm)
        guard !gone.isEmpty else { return false }
        library.games.removeAll { $0.titleID.uppercased() == id }
        try library.save(root: root)
        let mirror = ShellInstall.frameworksMirror(root: root) + "/"
        for game in gone where game.framework.hasPrefix(mirror) { ShellInstall.discard(game.framework, fm: fm, background: false) }
        return true
    }
}
