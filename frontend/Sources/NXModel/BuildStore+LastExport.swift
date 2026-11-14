import Foundation
import NXCore

// The last export, remembered: step 3 (send or copy the game data) stays open after the launcher starts again. A build still
// clears it: a game built after the IPA is not in it, and iOS loads a game's code only from inside the app.

extension BuildStore {
    nonisolated static let lastExportKey = "lastExport"

    /// The IPA the last export made, with the team it was signed for (empty: unsigned) and its kind.
    struct LastExport: Codable, Equatable {
        var path: String
        var team: String
        var oneGame: Bool
    }

    var lastExport: LastExport? {
        defaults.data(forKey: Self.lastExportKey).flatMap { try? JSONDecoder().decode(LastExport.self, from: $0) }
    }

    /// Saves the export as it is now, or forgets it when there is none.
    func rememberExport() {
        guard !exportedIPAPath.isEmpty else { defaults.removeObject(forKey: Self.lastExportKey); return }
        let saved = LastExport(path: exportedIPAPath, team: devices.ipaTeam, oneGame: devices.exportOneGame)
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.lastExportKey) }
    }

    /// At start: the last export comes back when its IPA is still there and the settings still make that kind of IPA for that team.
    func restoreLastExport() {
        guard exportedIPAPath.isEmpty, let saved = lastExport else { return }
        guard FileManager.default.fileExists(atPath: saved.path), saved.oneGame == devices.exportOneGame, saved.team == devices.ipaTeam else {
            defaults.removeObject(forKey: Self.lastExportKey)
            return
        }
        exportedIPAPath = saved.path
    }
}
