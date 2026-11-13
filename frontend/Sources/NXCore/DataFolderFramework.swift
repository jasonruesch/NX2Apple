import CryptoKit
import Foundation

/// A game's framework signed for the shared IPA's team, to go with the game's data: `DmGame<ID>.framework` beside `romfs.img`
/// and `msl/` in the game's folder on a drive or in the app's `Documents/games/<ID>/`. A shared app signed for that team copies
/// it into its `Documents/Frameworks` and loads it (ShellHost's `DataFolderFrameworks`), so a game built after the IPA plays
/// without a new IPA. The copy carries no shaders: its `msl/` goes beside it, and `external-msl.json` takes its place, as in an
/// IPA whose shaders were moved out.
///
/// The signed copy is kept at `<shell root>/data-frameworks/DmGame<ID>.framework` with a stamp of what it was made from, so it
/// is signed again only after the game is built again or for another team.
package enum DataFolderFramework {
    package static func folder(root: String) -> String { root + "/data-frameworks" }

    package static func signedCopy(root: String, titleID: String) -> String {
        folder(root: root) + "/DmGame\(titleID.uppercased()).framework"
    }

    static func stampFile(root: String, titleID: String) -> String {
        folder(root: root) + "/DmGame\(titleID.uppercased()).json"
    }

    /// What a signed copy was made from: the source framework's manifest and executable, and the team.
    struct Stamp: Codable, Equatable {
        var source: String
        var manifest: String
        var executableSize: Int64
        var executableModified: Double
        var team: String
    }

    /// The framework a game's signed copy is made from: shell.json's, else the launcher's mirror of it. Only a framework that
    /// carries its own host (`loader` FH) loads from outside the app, so any other is nil.
    package static func source(root: String, titleID: String, fm: FileManager = .default) -> String? {
        let upper = titleID.uppercased()
        guard !root.isEmpty, !upper.isEmpty else { return nil }
        let framework = ShellLibrary.load(root: root).games.first { $0.titleID.uppercased() == upper }?.framework
            ?? ShellInstall.mirroredFramework(root: root, titleID: upper)
        return ShellHotInstall.supportsHotPush(framework: framework, titleID: upper, fm: fm) ? framework : nil
    }

    static func stamp(of source: String, titleID: String, team: String, fm: FileManager) -> Stamp? {
        guard let manifest = fm.contents(atPath: source + "/game.manifest.json"),
              let json = (try? JSONSerialization.jsonObject(with: manifest)) as? [String: Any] else { return nil }
        let exe = (json["framework_executable"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "DmGame\(titleID.uppercased())"
        guard let attributes = try? fm.attributesOfItem(atPath: source + "/" + exe),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return Stamp(source: source, manifest: String(decoding: manifest, as: UTF8.self), executableSize: size,
                     executableModified: modified.timeIntervalSince1970, team: team)
    }

    static func savedStamp(root: String, titleID: String, fm: FileManager) -> Stamp? {
        fm.contents(atPath: stampFile(root: root, titleID: titleID)).flatMap { try? JSONDecoder().decode(Stamp.self, from: $0) }
    }

    /// The signed copy is there and was made from the game's current framework for `team`.
    package static func isCurrent(root: String, titleID: String, team: String, fm: FileManager = .default) -> Bool {
        guard let source = source(root: root, titleID: titleID, fm: fm),
              fm.fileExists(atPath: signedCopy(root: root, titleID: titleID)),
              let now = stamp(of: source, titleID: titleID, team: team, fm: fm) else { return false }
        return savedStamp(root: root, titleID: titleID, fm: fm) == now
    }

    /// Makes the signed copy unless it is current: the source framework without `msl/` (and the `msl-<UUID>.aar` archives an
    /// earlier export left), with `external-msl.json`, extended attributes cleared and signed with `identity`. `sign` runs a
    /// command and returns its exit status. Returns nil when the copy is ready, else what went wrong. A failure leaves the
    /// previous copy as it was.
    package static func prepare(root: String, titleID: String, team: String, identity: String,
                                sign: ([String]) -> Int32, codesign: String = "/usr/bin/codesign",
                                fm: FileManager = .default) -> String? {
        let upper = titleID.uppercased()
        guard let source = source(root: root, titleID: upper, fm: fm) else { return "no framework that loads from outside the app" }
        if isCurrent(root: root, titleID: upper, team: team, fm: fm) { return nil }
        guard let stamp = stamp(of: source, titleID: upper, team: team, fm: fm) else { return "the framework's manifest or executable is missing" }
        let work = folder(root: root) + "/.work-\(upper)-\(UUID().uuidString.prefix(8))"
        defer { try? fm.removeItem(atPath: work) }
        let copy = work + "/DmGame\(upper).framework"
        do {
            try fm.createDirectory(atPath: work, withIntermediateDirectories: true)
            try fm.copyItem(atPath: source, toPath: copy)
            let shaders = URL(fileURLWithPath: copy + "/msl", isDirectory: true)
            let stats = ShellExport.directoryStats(at: shaders, fm: fm)
            try? fm.removeItem(at: shaders)
            for name in (try? fm.contentsOfDirectory(atPath: copy)) ?? [] where name.hasPrefix("msl-") && name.hasSuffix(".aar") {
                try? fm.removeItem(atPath: copy + "/" + name)
            }
            if stats.files > 0 {
                let marker: [String: Any] = ["schema": 1, "files": stats.files, "bytes": stats.bytes]
                try JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys])
                    .write(to: URL(fileURLWithPath: copy + "/" + ShellExport.externalMSLMarker), options: .atomic)
            }
        } catch {
            return error.localizedDescription
        }
        _ = sign(ShellHotInstall.cleanFrameworkAttributesCommand(framework: copy))
        let status = sign(ShellHotInstall.codesignFrameworkCommand(codesign: codesign, identity: identity, framework: copy))
        guard status == 0 else { return "codesign exited with status \(status)" }
        let target = signedCopy(root: root, titleID: upper)
        do {
            if fm.fileExists(atPath: target) { try fm.removeItem(atPath: target) }
            try fm.moveItem(atPath: copy, toPath: target)
            let data = try JSONEncoder().encode(stamp)
            try data.write(to: URL(fileURLWithPath: stampFile(root: root, titleID: upper)), options: .atomic)
        } catch {
            return error.localizedDescription
        }
        return nil
    }

    /// Adds the signed copy's files as `DmGame<ID>.framework/…` and the source framework's shaders as `msl/…` to a game's data
    /// files, when the signed copy is current for whichever team it was signed for. Nothing changes otherwise.
    package static func addFiles(to sizes: inout [String: Int64], origins: inout [String: String], root: String, titleID: String,
                                 fm: FileManager = .default) {
        let upper = titleID.uppercased()
        guard let saved = savedStamp(root: root, titleID: upper, fm: fm),
              isCurrent(root: root, titleID: upper, team: saved.team, fm: fm) else { return }
        let copy = signedCopy(root: root, titleID: upper)
        let name = (copy as NSString).lastPathComponent
        for (rel, size) in ShellInstall.localFiles(in: copy) {
            sizes[name + "/" + rel] = size
            origins[name + "/" + rel] = copy + "/" + rel
        }
        let shaders = saved.source + "/msl"
        for (rel, size) in ShellInstall.localFiles(in: shaders) {
            sizes["msl/" + rel] = size
            origins["msl/" + rel] = shaders + "/" + rel
        }
    }

    /// The signed copies of `titleIDs`, made where needed with this Mac's development certificate for `team`. Nothing happens
    /// without a team (an unsigned IPA cannot load a framework from outside it) or without the certificate. `log` gets one line
    /// per game signed or skipped.
    package static func prepareAll(titleIDs: [String], root: String, team: String, runner: ProcessRunner,
                                   identity: ((String, ProcessRunner) -> String?) = ShellHotInstall.defaultSigningIdentity,
                                   codesign: String = "/usr/bin/codesign", log: (String) -> Void) {
        guard !team.isEmpty, !root.isEmpty else { return }
        let pending = titleIDs.filter { source(root: root, titleID: $0) != nil && !isCurrent(root: root, titleID: $0, team: team) }
        guard !pending.isEmpty else { return }
        guard let signer = identity(team, runner), !signer.isEmpty else {
            log("game code with game data: no development certificate for team \(team) on this Mac, the game data goes without it\n")
            return
        }
        for titleID in pending {
            let failure = prepare(root: root, titleID: titleID, team: team, identity: signer, sign: { command in
                runner.capture(ProcessLaunch(command)).status
            }, codesign: codesign)
            if let failure {
                log("game code with game data: \(titleID): not signed (\(failure)), the game data goes without it\n")
            } else {
                log("game code with game data: \(titleID): signed for team \(team)\n")
            }
        }
    }

    // MARK: Sending it again after it changes

    /// The game data copies compare files by size, and a framework signed again can keep every size. These say when the copy
    /// at the other end is not the current one, so its files go again.

    package static func prefix(titleID: String) -> String { "DmGame\(titleID.uppercased()).framework/" }

    package static func withoutFramework(_ files: [String: Int64], titleID: String) -> [String: Int64] {
        let start = prefix(titleID: titleID)
        return files.filter { !$0.key.hasPrefix(start) }
    }

    /// Which signature a framework folder carries: its resource seal and the end of its executable, where the code signature
    /// sits. nil when either is missing.
    package static func signatureDigest(of framework: String, fm: FileManager = .default) -> String? {
        guard let manifest = fm.contents(atPath: framework + "/game.manifest.json"),
              let json = (try? JSONSerialization.jsonObject(with: manifest)) as? [String: Any],
              let exe = (json["framework_executable"] as? String).flatMap({ $0.isEmpty ? nil : $0 }),
              let seal = fm.contents(atPath: framework + "/_CodeSignature/CodeResources"),
              let handle = FileHandle(forReadingAtPath: framework + "/" + exe) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let tail: UInt64 = 256 * 1024
        try? handle.seek(toOffset: end > tail ? end - tail : 0)
        guard let last = try? handle.readToEnd() else { return nil }
        var hash = SHA256()
        hash.update(data: seal)
        hash.update(data: last)
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The current signed copy's signature, or nil when there is no current copy (nothing of it goes with the data then).
    package static func currentDigest(root: String, titleID: String, fm: FileManager = .default) -> String? {
        guard let saved = savedStamp(root: root, titleID: titleID, fm: fm),
              isCurrent(root: root, titleID: titleID, team: saved.team, fm: fm) else { return nil }
        return signatureDigest(of: signedCopy(root: root, titleID: titleID), fm: fm)
    }

    /// What a drive holds of a game (`have`), less its framework when the copy in any of `gameFolders` is not the current
    /// signed copy, so the drive copy writes it again.
    package static func forgetChangedCopy(in have: [String: Int64], gameFolders: [String], root: String, titleID: String,
                                          fm: FileManager = .default) -> [String: Int64] {
        let start = prefix(titleID: titleID)
        guard have.keys.contains(where: { $0.hasPrefix(start) }) else { return have }
        let current = currentDigest(root: root, titleID: titleID, fm: fm)
        for folder in gameFolders {
            let copy = folder + "/" + String(start.dropLast())
            guard fm.fileExists(atPath: copy) else { continue }
            if current == nil || signatureDigest(of: copy, fm: fm) != current { return withoutFramework(have, titleID: titleID) }
        }
        return have
    }

    /// Removes the framework from a game's folder on a drive when it is not the current signed copy, so the drive copy (which
    /// skips files of the same size) writes the current one whole. Nothing changes without a current copy.
    package static func removeChangedCopy(in gameFolder: String, root: String, titleID: String, fm: FileManager = .default) {
        guard let current = currentDigest(root: root, titleID: titleID, fm: fm) else { return }
        let copy = gameFolder + "/" + String(prefix(titleID: titleID).dropLast())
        guard fm.fileExists(atPath: copy), signatureDigest(of: copy, fm: fm) != current else { return }
        try? fm.removeItem(atPath: copy)
    }
}
