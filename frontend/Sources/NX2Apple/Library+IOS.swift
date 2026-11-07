import Foundation
import NXCore

// What the library records about a game's iPhone / iPad build: the shared app installed on a device, or an exported IPA.

/// The kinds of IPA an export makes, as `LibraryGame.ipaKind` stores them.
enum IPAKind: String {
    case shared, oneGame
}

extension GameLibrary {
    func recordCompletedIOS(archive: String, app: String, device: String = "", commit: String = "", for id: UUID) {
        guard var game = games.first(where: { $0.id == id }),
              FileManager.default.fileExists(atPath: app + "/Info.plist") else { return }
        // The shared app replaces an older build's single IPA: the file stays on disk, the library stops listing it
        game.ipaPath = ""
        game.ipaKind = ""
        if !archive.isEmpty { game.archivePath = archive }
        game.iosAppPath = app
        game.installedDevice = device
        game.toolsCommit = commit
        upsert(game)
        recordSharedAppInstalled(app: app, device: device)
    }

    /// An export ended well: the game's own IPA, or the shared app's, which holds every game in the shell folder's shell.json. A game
    /// whose shared app is installed on a device keeps that as its status: the export does not change what is on the device.
    func recordExportedIPA(_ ipa: String, kind: IPAKind, archive: String = "", shellRoot: String = "", commit: String = "", for id: UUID) {
        guard var game = games.first(where: { $0.id == id }), FileManager.default.fileExists(atPath: ipa) else { return }
        if !archive.isEmpty { game.archivePath = archive }
        game.toolsCommit = commit
        game.ipaPath = ipa
        game.ipaKind = kind.rawValue
        upsert(game)
        guard kind == .shared, !shellRoot.isEmpty else { return }
        applySharedIPA(ipa, titles: Set(ShellLibrary.load(root: shellRoot).games.map { $0.titleID.uppercased() }), keepRecorded: false)
    }

    /// A game build added the game to the shared app: it waits for the iPhone app page to make the app. Its archive is the game data
    /// that goes over after an install or export.
    func recordAddedToSharedApp(archive: String, commit: String = "", for id: UUID) {
        guard var game = games.first(where: { $0.id == id }) else { return }
        if !archive.isEmpty { game.archivePath = archive }
        game.toolsCommit = commit
        game.addedToSharedApp = true
        upsert(game)
    }

    /// The iPhone app page exported the shared app: every game in shell.json is in that IPA.
    func recordSharedExport(_ ipa: String, shellRoot: String) {
        guard FileManager.default.fileExists(atPath: ipa) else { return }
        applySharedIPA(ipa, titles: Set(ShellLibrary.load(root: shellRoot).games.map { $0.titleID.uppercased() }), keepRecorded: false)
    }

    /// A game taken out of the shared app: it no longer waits for it, and the shared app's IPA or install is no longer its status.
    func recordRemovedFromSharedApp(titleID: String) {
        updateGames { game in
            guard game.titleID.caseInsensitiveCompare(titleID) == .orderedSame,
                  game.addedToSharedApp || game.ipaKind == IPAKind.shared.rawValue || game.hasSharedApp else { return false }
            game.addedToSharedApp = false
            if game.ipaKind == IPAKind.shared.rawValue { game.ipaPath = ""; game.ipaKind = "" }
            if game.hasSharedApp { game.iosAppPath = ""; game.installedDevice = "" }
            return true
        }
    }

    /// The shared app's IPA from an export the library did not record (one made before the launcher recorded exports): the games in
    /// shell.json are in it when the IPA is newer than shell.json, which every export writes first and an install writes again. A game
    /// with an exported IPA of its own or an installed shared app keeps it.
    func syncExportedIPA(root: String) {
        let fm = FileManager.default
        let ipa = ShellInstall.ipaPath(root: root), state = ShellLibrary.stateFile(root: root)
        guard let made = (try? fm.attributesOfItem(atPath: ipa))?[.modificationDate] as? Date,
              let listed = (try? fm.attributesOfItem(atPath: state))?[.modificationDate] as? Date,
              made >= listed else { return }
        applySharedIPA(ipa, titles: Set(ShellLibrary.load(root: root).games.map { $0.titleID.uppercased() }), keepRecorded: true)
    }

    /// Lists the shared IPA for the games in `titles`, except those with the shared app installed (and, with `keepRecorded`, those
    /// with an exported IPA already).
    private func applySharedIPA(_ ipa: String, titles: Set<String>, keepRecorded: Bool) {
        guard !titles.isEmpty else { return }
        updateGames { game in
            guard titles.contains(game.titleID.uppercased()), !(keepRecorded && (game.hasSharedApp || game.hasExportedIPA)) else { return false }
            guard game.ipaPath != ipa || game.ipaKind != IPAKind.shared.rawValue || game.addedToSharedApp else { return false }
            game.ipaPath = ipa
            game.ipaKind = IPAKind.shared.rawValue
            game.addedToSharedApp = false
            return true
        }
    }

    /// Every game in the shared app's shell.json is inside `app` on `device` once the shared app is signed and installed there.
    func recordSharedAppInstalled(app: String, device: String) {
        guard !device.isEmpty,
              FileManager.default.fileExists(atPath: app + "/Info.plist"),
              let shell = ShellInstall.paths(ofApp: app) else { return }
        applySharedAppInstalled(titles: ShellLibrary.recordInstalled(root: shell.root), app: app, device: device)
    }

    private func applySharedAppInstalled(titles: Set<String>, app: String, device: String) {
        guard !device.isEmpty, !titles.isEmpty else { return }
        updateGames { game in
            guard titles.contains(game.titleID.uppercased()),
                  game.iosAppPath != app || game.installedDevice != device || !game.ipaPath.isEmpty || game.addedToSharedApp else { return false }
            game.ipaPath = ""
            game.ipaKind = ""
            game.addedToSharedApp = false
            game.iosAppPath = app
            game.installedDevice = device
            return true
        }
    }

    /// Restores the shared app's games from the last successful install receipt when `DmShell.app` is signed on disk
    /// (`embedded.mobileprovision` is present) and at least one receipt member still has recorded shared-app install provenance.
    func syncSharedApp(root: String) {
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
