import Foundation

/// What the shell app's real launcher applies to start one game's engine: the environment (set with overwrite, before
/// the engine reads anything), the `dm_main` arguments and the framework to load. Computed from a `LaunchableGame` and
/// the app's locations, mirroring `boot_env()` in `dm/ios/Sources/main.m` and the table in `docs/launcher-c-plan.md`
/// ("Environment at game start"). Pure: the only side effect is `createFolders()`, called explicitly.
public struct EngineLaunchPlan: Equatable, Sendable {
    /// Set with overwrite, before the engine reads anything.
    public var environment: [String: String]
    /// `dm_main` argv: `["dmhost", "<framework>/dm", <manifest modules...>]`.
    public var arguments: [String]
    /// `<framework>/<manifest.framework_executable>`.
    public var frameworkExecutable: URL
    /// `manifest.image_marker`: the symbol or section that tells the loader which image is the game's.
    public var imageMarker: String
    /// `Documents/log.txt`, the engine log the per-game app also writes.
    public var logURL: URL
    /// `Documents`.
    public var workingDirectory: URL
    /// The save and temp folders.
    public var foldersToCreate: [URL]

    /// `envFileText` is the shared `Documents/env.txt`. `gameEnvFileText` is the game's own `Documents/games/<title ID>/env.txt`
    /// (#557), read from `game.appFolder` when it is nil. A key in the game's file wins over the shared file, and the launch
    /// environment (the player's settings, the paths above) wins over both. The game's own `mods/` folder sets
    /// `DM_ROMFS_OVERLAY` (`GameMods`) when the game's env file does not, and it wins over the shared file. The order is: launch
    /// environment, game env.txt, game mods folder, shared env.txt, framework dm/env.txt.
    /// The framework file carries build-time defaults such as CPU BC decoding for older GPUs (#719). Automatic `DM_PSO_BUNDLE`
    /// discovery is a fallback after all env files, so an explicit archive path or `off` can override it.
    /// Whether `msl` holds the libraries of the chain the game was built with: `b-<chain>.img` or `b-<chain>/`, or `vk/` or `gl/`
    /// for a Vulkan or GL game, the paths the engine reads under `DM_MSL_DIR`. Shaders copied for an older build of the game's code
    /// would not load.
    static func holdsShaders(_ msl: URL, chain: String, fileManager fm: FileManager = .default) -> Bool {
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: msl.appendingPathComponent(chain + ".img").path, isDirectory: &isDir), !isDir.boolValue { return true }
        return [chain, "vk", "gl"].contains { fm.fileExists(atPath: msl.appendingPathComponent($0).path, isDirectory: &isDir) && isDir.boolValue }
    }

    /// The game's own shaders, outside the IPA: `msl/` in its app folder (`Documents/games/<title ID>/`, where the launcher's copy to
    /// the device puts them), else `msl/` beside its data (on a drive or in a picked folder, next to the RomFS). Each counts only when
    /// it holds the game's chain (`holdsShaders`), so stale shaders fall back to the IPA's own.
    static func ownShaders(for game: LaunchableGame, fileManager fm: FileManager = .default) -> URL? {
        [game.appFolder, game.dataURL].map { $0.appendingPathComponent("msl", isDirectory: true) }
            .first { holdsShaders($0, chain: game.manifest.chain, fileManager: fm) }
    }

    /// The IPA left the game's shaders out (GameShaders.externalMarker in the Mac launcher) and neither the app folder nor the data
    /// folder holds them: the game cannot start until its game data, which carries them, is copied again.
    public static func shadersMissing(framework: URL, chain: String, appFolder: URL, dataFolder: URL?, fileManager fm: FileManager = .default) -> Bool {
        guard fm.fileExists(atPath: framework.appendingPathComponent(externalShadersMarker).path) else { return false }
        return !([appFolder] + (dataFolder.map { [$0] } ?? [])).contains {
            holdsShaders($0.appendingPathComponent("msl", isDirectory: true), chain: chain, fileManager: fm)
        }
    }

    /// The file a framework holds instead of `msl/` when the IPA left its shaders out.
    public static let externalShadersMarker = "msl-with-game-data"

    public static func make(game: LaunchableGame, appResources: URL, documents: URL, envFileText: String?, gameEnvFileText: String? = nil,
                            fileManager fm: FileManager = .default) -> EngineLaunchPlan {
        let manifest = game.manifest, fw = game.frameworkURL, gdir = game.appFolder
        func isDirectory(_ url: URL) -> Bool {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
        var env: [String: String] = [:]

        let perGameProfile = gdir.appendingPathComponent("profile.tsv")
        env["DM_PROFILE"] = (fm.fileExists(atPath: perGameProfile.path) ? perGameProfile : fw.appendingPathComponent(manifest.profile)).path
        if let romfs = game.romfsURL ?? DataLocator.romfs(in: game.dataURL, manifest: manifest, fm)?.romfs {
            env["DM_ROMFS"] = romfs.path
        }
        let save = gdir.appendingPathComponent("save", isDirectory: true), temp = gdir.appendingPathComponent("temp", isDirectory: true)
        env["DM_SAVE"] = save.path
        env["DM_TEMP"] = temp.path
        env["DM_NVN_SHMAP"] = fw.appendingPathComponent(manifest.shaderMap).path
        let bundledMSL = game.shaderResourcesURL ?? fw.appendingPathComponent("msl", isDirectory: true)
        env["DM_MSL_DIR"] = (ownShaders(for: game, fileManager: fm) ?? bundledMSL).path
        let ownPSO = gdir.appendingPathComponent("pso", isDirectory: true), fwPSO = fw.appendingPathComponent("pso", isDirectory: true)
        let dataAOC = game.dataURL.appendingPathComponent("aoc", isDirectory: true), ownAOC = gdir.appendingPathComponent("aoc", isDirectory: true)
        if isDirectory(dataAOC) { env["DM_AOC_DIR"] = dataAOC.path } else if isDirectory(ownAOC) { env["DM_AOC_DIR"] = ownAOC.path }
        env["DM_CHEATS"] = gdir.appendingPathComponent("cheats", isDirectory: true).path
        env["DM_FONT_DIR"] = appResources.appendingPathComponent("dm/font", isDirectory: true).path
        if let cloud = game.cloudSavesURL { env["DM_SAVE_SYNC"] = cloud.path }
        // The shell already showed its own settings, the per-game launcher screen stays out of the way.
        env["DM_LAUNCHER"] = "0"
        for (key, value) in game.environment { env[key] = value }

        var fromFile: [String] = []
        let ownText = gameEnvFileText ?? fm.contents(atPath: gdir.appendingPathComponent("env.txt").path).flatMap { String(data: $0, encoding: .utf8) }
        func apply(_ text: String?) {
            for (key, value) in parseEnvFile(text ?? "") where env[key] == nil {
                env[key] = value
                fromFile.append(key)
            }
        }
        apply(ownText)
        if env["DM_ROMFS_OVERLAY"] == nil,
           let overlay = GameMods.overlay(in: gdir.appendingPathComponent("mods", isDirectory: true), titleID: game.titleID, fm) {
            env["DM_ROMFS_OVERLAY"] = overlay
        }
        apply(envFileText)
        apply(fm.contents(atPath: fw.appendingPathComponent("dm/env.txt").path).flatMap { String(data: $0, encoding: .utf8) })
        env["DM_ENV_FILE_KEYS"] = fromFile.joined(separator: " ")
        if env["DM_PSO_BUNDLE"] == nil {
            if isDirectory(ownPSO) { env["DM_PSO_BUNDLE"] = ownPSO.path } else if isDirectory(fwPSO) { env["DM_PSO_BUNDLE"] = fwPSO.path }
        }

        return EngineLaunchPlan(
            environment: env,
            arguments: ["dmhost", fw.appendingPathComponent("dm", isDirectory: true).path] + manifest.modules,
            frameworkExecutable: fw.appendingPathComponent(manifest.frameworkExecutable),
            imageMarker: manifest.imageMarker,
            logURL: documents.appendingPathComponent("log.txt"),
            workingDirectory: documents,
            foldersToCreate: [save, temp])
    }

    /// Creates the save and temp folders (and their parents) when they are missing. The temp folder is kept out of the backup, the
    /// save folder stays in it (`BackupExclusion`, #618).
    public func createFolders(fileManager fm: FileManager = .default) throws {
        for url in foldersToCreate {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            if !GameDeletion.isSave(url.lastPathComponent) { BackupExclusion.exclude(url) }
        }
    }

    /// `KEY=VALUE` lines in order: `#` starts a comment line, blank lines and lines without `=` or with an empty key
    /// are skipped, whitespace around a line is trimmed (as `boot_env` reads `env.txt`).
    public static func parseEnvFile(_ text: String) -> [(key: String, value: String)] {
        var result: [(key: String, value: String)] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "="), eq != line.startIndex else { continue }
            result.append((key: String(line[..<eq]), value: String(line[line.index(after: eq)...])))
        }
        return result
    }
}
