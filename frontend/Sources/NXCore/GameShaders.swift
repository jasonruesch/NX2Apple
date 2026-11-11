import Foundation

/// A game's shaders beside its game data. The iPhone app reads `msl/` from the game's folder in `Documents/games/<title ID>/`, or
/// from the folder that holds its `romfs.img` on a drive, before the shaders in the IPA (EngineLaunchPlan.swift in frontend-ios). So when
/// the shared app's IPA leaves the shaders out, the copy of the game data to a device or a drive takes the framework's `msl/` along.
package enum GameShaders {
    /// The file an export that leaves a game's shaders out puts in its framework instead of `msl/`. The iPhone app asks for the game
    /// data again when neither the game's folder nor its data folder holds its shaders.
    package static let externalMarker = "msl-with-game-data"

    /// The files of the framework's `msl/`, as paths under the data folder (`msl/b-<chain>.img`) with their sizes.
    package static func files(framework: String) -> [String: Int64] {
        ShellInstall.localFiles(in: framework + "/msl").reduce(into: [:]) { $0["msl/" + $1.key] = $1.value }
    }

    /// The game data's files with the shaders the copy places beside them, for the size and space checks before the copy.
    package static func dataFiles(archive: String, framework: String?) -> [String: Int64] {
        let local = ShellInstall.localFiles(in: archive).filter { !$0.key.hasPrefix("msl/") }
        return local.merging(framework.map(files) ?? [:]) { _, shader in shader }
    }

    /// Makes `<archive>/msl/` hold what the framework's `msl/` holds: a file of the same size is kept, any other is copied (a clone on
    /// the same APFS volume), and a file the framework no longer has (the library of an older chain) is removed. A framework without
    /// `msl/` changes nothing. Returns how many files it copied.
    @discardableResult
    package static func place(framework: String, in archive: String, fm: FileManager = .default) throws -> Int {
        let source = framework + "/msl", target = archive + "/msl"
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: source, isDirectory: &isDir), isDir.boolValue else { return 0 }
        let want = ShellInstall.localFiles(in: source), have = ShellInstall.localFiles(in: target)
        for stale in have.keys where want[stale] == nil { try fm.removeItem(atPath: target + "/" + stale) }
        var copied = 0
        for (relative, size) in want.sorted(by: { $0.key < $1.key }) where have[relative] != size {
            let to = target + "/" + relative, partial = to + ".partial"
            try fm.createDirectory(atPath: (to as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? fm.removeItem(atPath: partial)
            try fm.copyItem(atPath: source + "/" + relative, toPath: partial)
            try? fm.removeItem(atPath: to)
            try fm.moveItem(atPath: partial, toPath: to)
            copied += 1
        }
        removeEmptyFolders(in: target, fm: fm)
        return copied
    }

    /// After a copy to a drive: removes the files of the game's `msl/` folder there that the copy did not send (the library of an
    /// older chain), so the drive holds only the shaders of the game's current build.
    package static func removeOthers(in destination: String, keeping files: [String: Int64], fm: FileManager = .default) {
        for relative in ShellInstall.localFiles(in: destination + "/msl").keys where files["msl/" + relative] == nil {
            try? fm.removeItem(atPath: destination + "/msl/" + relative)
        }
        removeEmptyFolders(in: destination + "/msl", fm: fm)
    }

    /// Leaves the game's shaders out of a staged framework: `msl/` and any packed `msl-<UUID>.aar` are removed and the marker is written.
    /// Returns whether the framework held shaders.
    @discardableResult
    package static func strip(framework: URL, fm: FileManager = .default) throws -> Bool {
        let names = (try? fm.contentsOfDirectory(atPath: framework.path)) ?? []
        let shaders = names.filter { $0 == "msl" || ($0.hasPrefix("msl-") && $0.hasSuffix(".aar")) }
        for name in shaders { try fm.removeItem(at: framework.appendingPathComponent(name)) }
        guard !shaders.isEmpty else { return false }
        try Data().write(to: framework.appendingPathComponent(externalMarker))
        return true
    }

    private static func removeEmptyFolders(in folder: String, fm: FileManager) {
        let entries = (try? fm.contentsOfDirectory(atPath: folder)) ?? []
        for name in entries {
            let path = folder + "/" + name
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            removeEmptyFolders(in: path, fm: fm)
            if ((try? fm.contentsOfDirectory(atPath: path)) ?? []).isEmpty { try? fm.removeItem(atPath: path) }
        }
    }
}
