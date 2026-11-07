import SwiftUI
import AppKit
import NXCore
import NXModel
import NXLauncher

// Batch builds: games picked in the library (Select, or Command-click a card) go to the queue (BuildQueue), which builds them one after
// another with the files the library remembers for each. The queue card on the Builds page shows where it stands.

extension LauncherView {
    /// A card's click: with Select on, or with Command held, it picks the game for a batch; otherwise it shows the game.
    func cardClicked(_ game: LibraryGame) {
        if selecting || NSEvent.modifierFlags.contains(.command) {
            if picked.contains(game.id) { picked.remove(game.id) } else { picked.insert(game.id) }
        } else {
            library.selectedID = game.id
        }
    }

    /// The picked games that can build: the library remembers their files.
    var pickedGames: [LibraryGame] {
        filteredGames.filter { picked.contains($0.id) }
    }

    func buildPicked(target: String) {
        let games = pickedGames.map { (id: $0.id, name: $0.name) }
        guard !games.isEmpty else { return }
        queue.enqueue(games, target: target, buildRunning: m.running)
        picked = []
        selecting = false
        page = .builds
    }

    /// Sets up one queued game as Build again does, for the queue's target, and starts it.
    func startQueued(_ id: UUID, target: String) -> BuildQueue.Start {
        guard let game = library.games.first(where: { $0.id == id }) else { return .skipped(loc.t("queue.gone")) }
        guard !m.running else { return .skipped(loc.t("queue.busy")) }
        let hasFiles = game.inputs[GameLibrary.folderInput]?.isEmpty == false || game.inputs["base", default: []].isEmpty == false
        guard hasFiles else { return .skipped(loc.t("queue.noFiles")) }
        configureBuild(game)
        m.target = target
        guard m.canBuild else { return .skipped(m.doneNote.isEmpty ? loc.t("queue.noFiles") : m.doneNote) }
        m.startBuild()
        if m.running || !m.staleFrameworks.isEmpty { return .started }
        return .skipped(m.doneNote)
    }

    /// The stale frameworks question was answered: Stop ended the queued build before it ran, Continue started it.
    func staleAnswered() {
        DispatchQueue.main.async {
            guard !m.running, queue.building != nil else { return }
            queue.buildEnded(ok: false, note: loc.t("msg.stopped"))
        }
    }

    /// The bar over the collection while games are picked: how many, and the two targets to build them for.
    @ViewBuilder var selectionBar: some View {
        if selecting || !picked.isEmpty {
            HStack(spacing: 14) {
                Text(picked.isEmpty ? loc.t("queue.pickHint") : String(format: loc.t("queue.picked"), picked.count))
                    .font(.manrope(14, .semibold))
                Spacer()
                Button(loc.t("queue.buildIOS")) { buildPicked(target: BuildTarget.ios) }.disabled(picked.isEmpty)
                Button(loc.t("queue.buildMac")) { buildPicked(target: BuildTarget.mac) }.disabled(picked.isEmpty)
                Button(loc.t("queue.selectDone")) { picked = []; selecting = false }
            }
            .buttonStyle(LauncherSecondaryButtonStyle())
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(LauncherPalette.surface, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
