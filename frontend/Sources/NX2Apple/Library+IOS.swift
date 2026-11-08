import Foundation
import NXCore

// What the library records about a game's iPhone / iPad build: only what the disk cannot say. Whether a game is in the shared app, in
// its exported IPA or on the device is read from the shell folder (SharedAppState, GameLibrary.shared); what is kept here is the
// device the shared app went to, a one-game IPA's path, and the game data and engine commit of the last build.

extension GameLibrary {
    func recordCompletedIOS(archive: String, app: String, device: String = "", commit: String = "", for id: UUID) {
        guard var game = games.first(where: { $0.id == id }),
              FileManager.default.fileExists(atPath: app + "/Info.plist") else { return }
        // The shared app replaces an older build's single IPA: the file stays on disk, the library stops listing it
        game.ipaPath = ""
        if !archive.isEmpty { game.archivePath = archive }
        game.iosAppPath = app
        game.installedDevice = device
        game.toolsCommit = commit
        upsert(game)
        recordSharedAppInstalled(app: app, device: device)
    }

    /// One game's own IPA, with its data inside, was exported.
    func recordOneGameIPA(_ ipa: String, commit: String = "", for id: UUID) {
        guard var game = games.first(where: { $0.id == id }), FileManager.default.fileExists(atPath: ipa) else { return }
        game.toolsCommit = commit
        game.ipaPath = ipa
        upsert(game)
    }

    /// A game build added the game to the shared app: its game data (for the send after an install or export) and the engine commit.
    /// The shell folder says that it is in the shared app.
    func recordAddedToSharedApp(archive: String, commit: String = "", for id: UUID) {
        guard var game = games.first(where: { $0.id == id }) else { return }
        if !archive.isEmpty { game.archivePath = archive }
        game.toolsCommit = commit
        upsert(game)
    }

    /// Reads the shell folder again: which games are in the shared app, when each was built, the last install and export. Published
    /// only when it changed, so a refresh redraws nothing otherwise.
    func refreshShared(root: String) {
        let state = SharedAppState.read(root: root)
        if state != shared { shared = state }
    }

    /// The device the shared app went to, for every game in shell.json, once it is signed and installed there.
    func recordSharedAppInstalled(app: String, device: String) {
        guard !device.isEmpty,
              FileManager.default.fileExists(atPath: app + "/Info.plist"),
              let shell = ShellInstall.paths(ofApp: app) else { return }
        applySharedAppInstalled(titles: ShellLibrary.recordInstalled(root: shell.root), app: app, device: device)
        refreshShared(root: shell.root)
    }

    private func applySharedAppInstalled(titles: Set<String>, app: String, device: String) {
        guard !device.isEmpty, !titles.isEmpty else { return }
        updateGames { game in
            guard titles.contains(game.titleID.uppercased()),
                  game.iosAppPath != app || game.installedDevice != device || !game.ipaPath.isEmpty else { return false }
            game.ipaPath = ""
            game.iosAppPath = app
            game.installedDevice = device
            return true
        }
    }

    /// Restores the shared app's games from the last successful install receipt when `DmShell.app` is signed on disk
    /// (`embedded.mobileprovision` is present) and at least one receipt member still has recorded shared-app install provenance.
    func syncSharedApp(root: String) {
        refreshShared(root: root)
        let app = ShellInstall.appPath(root: root)
        guard FileManager.default.fileExists(atPath: app + "/" + AppSignature.profileName) else { return }
        let receipt = ShellLibrary.installedReceipt(root: root)
        guard !receipt.isEmpty,
              let device = games.first(where: {
                  receipt.contains($0.titleID.uppercased())
                      && !$0.installedDevice.isEmpty
                      && ShellInstall.paths(ofApp: $0.iosAppPath) != nil
              })?.installedDevice else { return }
        applySharedAppInstalled(titles: receipt, app: app, device: device)
    }
}
