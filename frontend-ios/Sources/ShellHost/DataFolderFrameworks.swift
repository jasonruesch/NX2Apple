import CryptoKit
import Foundation
import os

private let logger = Logger(subsystem: "dev.nx2apple.shell", category: "data-frameworks")

/// Game frameworks the Mac launcher signed for this app's team and copied with the game data, as `DmGame<ID>.framework` next to
/// `romfs.img` and `msl/` in the game's folder (on a drive, in the shell data folder, or in `Documents/games/<ID>/`). A new or
/// changed one is copied into `Documents/Frameworks` through the staging folder and `.ready` marker a hot push uses, so
/// `GameCatalogue.promoteStagedFrameworks` checks it and moves it into place. The app then plays a game it was not exported
/// with, without a new IPA.
public enum DataFolderFrameworks {
    /// What was last copied in for each title ID, kept in the hot folder, so a framework the catalogue sets aside later (an older
    /// build than the app's own, say) is not copied in again at every start.
    static let recordName = ".data-frameworks.json"
    /// How many folder entries a look through one data folder lists at most (an external drive can hold a lot).
    static let maxEntries = 2000

    /// `DmGame<ID>.framework` folders in `folder` and in its subfolders one and two levels down, the depth `ShellDataIndex`
    /// reads for `romfs.img`. Hidden items and symbolic links are skipped, and at most `maxEntries` entries are listed.
    public static func candidates(in folder: URL, fileManager fm: FileManager = .default) -> [URL] {
        var seen = 0
        var found: [URL] = []
        func visit(_ dir: URL, depth: Int) {
            let urls = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                     options: [.skipsHiddenFiles])) ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            seen += urls.count
            for url in urls where seen <= maxEntries {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isSymbolicLink != true, values?.isDirectory == true else { continue }
                let name = url.lastPathComponent
                if name.hasPrefix("DmGame"), name.hasSuffix(".framework") {
                    found.append(url)
                } else if depth < 2 {
                    visit(url, depth: depth + 1)
                }
            }
        }
        visit(folder, depth: 0)
        return found
    }

    /// The Apple developer team that signed `executable`, read from its code signature without loading it.
    public static func signingTeam(of executable: URL) -> String? {
        FrameworkSignature.inspect(executable: executable)?.teamID
    }

    /// Copies each framework found in `folders` into `hotRoot` as a staged hot framework when it is signed for `hostTeam`, differs
    /// from what the app has for that game (the hot copy, else the one inside the app), and is not the one copied in last time.
    /// The first folder that holds a game wins. Returns the title IDs staged. Nothing happens without a host team: an app that
    /// is not signed for a team cannot load a framework from outside its bundle.
    @discardableResult
    public static func importAll(from folders: [URL], hotRoot: URL, gamesRoot: URL, hostTeam: String?,
                                 teamOf: (URL) -> String? = signingTeam(of:),
                                 fileManager fm: FileManager = .default) -> [String] {
        guard let hostTeam, !hostTeam.isEmpty else { return [] }
        var record = loadRecord(hotRoot: hotRoot, fm: fm)
        let before = record
        var staged: [String] = []
        var handled = Set<String>()
        for folder in folders {
            for framework in candidates(in: folder, fileManager: fm) {
                let entry = GameCatalogue.readFramework(at: framework, fileManager: fm)
                guard entry.problem == nil, let manifest = entry.manifest else { continue }
                let id = manifest.titleID.uppercased()
                guard isTitleID(id), handled.insert(id).inserted else { continue }
                let executable = framework.appendingPathComponent(manifest.frameworkExecutable)
                guard teamOf(executable) == hostTeam else {
                    logger.info("\(id, privacy: .public): the framework beside the game data is not signed for team \(hostTeam, privacy: .public), not loaded")
                    continue
                }
                guard let print = fingerprint(of: framework, executable: manifest.frameworkExecutable, fm: fm),
                      record[id] != print else { continue }
                let hot = hotRoot.appendingPathComponent("DmGame\(id).framework", isDirectory: true)
                let current = fm.fileExists(atPath: hot.path) ? hot : gamesRoot.appendingPathComponent(manifest.framework, isDirectory: true)
                if sameBuild(framework, current, executable: manifest.frameworkExecutable, fm: fm) {
                    record[id] = print
                    continue
                }
                if stage(framework, titleID: id, in: hotRoot, fm: fm) {
                    record[id] = print
                    staged.append(id)
                    logger.info("\(id, privacy: .public): copied the framework beside the game data into Documents/Frameworks")
                }
            }
        }
        if record != before { saveRecord(record, hotRoot: hotRoot, fm: fm) }
        return staged
    }

    /// The same build of a game: the same manifest and an executable of the same size. The signatures differ between the copy
    /// inside the app and the launcher's copy beside the game data, so they are not compared.
    static func sameBuild(_ a: URL, _ b: URL, executable: String, fm: FileManager) -> Bool {
        guard let manifestA = fm.contents(atPath: a.appendingPathComponent("game.manifest.json").path),
              let manifestB = fm.contents(atPath: b.appendingPathComponent("game.manifest.json").path),
              manifestA == manifestB else { return false }
        return size(of: a.appendingPathComponent(executable), fm) == size(of: b.appendingPathComponent(executable), fm)
    }

    /// The manifest, the executable's size and the signature's resource seal: the launcher signs again only when the game was
    /// built again, so this stays the same until then.
    static func fingerprint(of framework: URL, executable: String, fm: FileManager) -> String? {
        guard let manifest = fm.contents(atPath: framework.appendingPathComponent("game.manifest.json").path),
              let exeSize = size(of: framework.appendingPathComponent(executable), fm) else { return nil }
        let seal = fm.contents(atPath: framework.appendingPathComponent("_CodeSignature/CodeResources").path) ?? Data()
        func hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        return "\(hex(manifest)):\(exeSize):\(hex(seal))"
    }

    private static func size(of url: URL, _ fm: FileManager) -> Int64? {
        (try? fm.attributesOfItem(atPath: url.path))?[.size].flatMap { ($0 as? NSNumber)?.int64Value }
    }

    /// `hotRoot/.staging-<ID>-<token>/DmGame<ID>.framework` and its `.ready`, written last. A copy that fails leaves nothing.
    private static func stage(_ framework: URL, titleID: String, in hotRoot: URL, fm: FileManager) -> Bool {
        let staging = hotRoot.appendingPathComponent(HotFrameworkReady.stagingPrefix + titleID + "-" + UUID().uuidString.prefix(8).lowercased(),
                                                     isDirectory: true)
        let target = staging.appendingPathComponent("DmGame\(titleID).framework", isDirectory: true)
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try fm.copyItem(at: framework, to: target)
            // A drive formatted exFAT holds the Mac's `._*` metadata files: they are not part of the framework
            let metadata = (fm.subpaths(atPath: target.path) ?? []).filter {
                let name = ($0 as NSString).lastPathComponent
                return name == ".DS_Store" || name.hasPrefix("._")
            }
            for rel in metadata { try fm.removeItem(atPath: target.path + "/" + rel) }
            guard let footprint = GameCatalogue.frameworkFootprint(at: target, fileManager: fm) else {
                throw CocoaError(.fileReadUnknown)
            }
            let ready = HotFrameworkReady(titleID: titleID, files: footprint.files, bytes: footprint.bytes)
            try JSONEncoder().encode(ready).write(to: staging.appendingPathComponent(HotFrameworkReady.fileName), options: .atomic)
            return true
        } catch {
            logger.error("\(titleID, privacy: .public): could not copy the framework beside the game data: \(error.localizedDescription, privacy: .public)")
            GameCatalogue.discardFolder(staging, in: hotRoot, fm: fm)
            return false
        }
    }

    private static func loadRecord(hotRoot: URL, fm: FileManager) -> [String: String] {
        guard let data = fm.contents(atPath: hotRoot.appendingPathComponent(recordName).path),
              let record = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return record
    }

    private static func saveRecord(_ record: [String: String], hotRoot: URL, fm: FileManager) {
        try? fm.createDirectory(at: hotRoot, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try? encoder.encode(record).write(to: hotRoot.appendingPathComponent(recordName), options: .atomic)
    }
}
