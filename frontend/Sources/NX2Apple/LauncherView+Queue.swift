import SwiftUI
import AppKit
import NXCore
import NXModel
import NXLauncher

// Batch builds: games picked in the library (Select, or Command-click a card) go to the queue (BuildQueue) without starting. The Builds
// page shows each game's files on request (the queue card), so the player can check or change them, and Build games starts the batch
// from its first game. Each then builds with the files the library remembers for it.

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
        queue.enqueue(games, target: target, buildRunning: m.running, start: false)
        picked = []
        selecting = false
        if let first = queue.selectedID { showQueued(first) }
        page = .builds
    }

    /// Shows a batch game's files in the Builds page's cards, to check or change them. The files of the game shown before are saved
    /// to the library first, with the target it was set to, so the batch builds what the player saw.
    func showQueued(_ id: UUID) {
        guard !m.running, let game = library.games.first(where: { $0.id == id }),
              let entry = queue.entries.first(where: { $0.id == id }) else { return }
        saveShownQueued()
        configureBuild(game, fromBatch: true)
        m.target = entry.target
        fillKnownKeys()
        queue.select(id)
    }

    /// One batch game built on its own: the files shown are saved first (they may be this game's, just changed), then it builds.
    func buildQueued(_ id: UUID) {
        guard !m.running else { return }
        saveShownQueued()
        queue.runOne(id)
    }

    /// The Build games button: saves the files shown, then starts the batch from its first game.
    func startQueue() {
        saveShownQueued()
        queue.startAll(buildRunning: m.running)
    }

    /// The files and target on the Builds page belong to the batch game it shows: kept in the library for that game's build.
    private func saveShownQueued() {
        guard queue.isShown, let shown = queue.selectedID, !m.basePath.isEmpty else { return }   // set aside: the page shows another game
        _ = library.rememberInputs(m)
        queue.setTarget(m.target, for: shown)
    }

    /// One prod.keys opens every game: a game the library found in the games folder has none saved, so it takes the one the other
    /// games were built with.
    private func fillKnownKeys() {
        guard m.gameFolder == nil, m.keysPath.isEmpty || !FileManager.default.fileExists(atPath: m.keysPath), let keys = knownKeys,
              let index = m.slots.firstIndex(where: { $0.id == "keys" }) else { return }
        m.slots[index].paths = [keys]
        m.slots[index].problem = ""
    }

    /// Sets up one queued game as Build again does, for the queue's target, and starts it.
    func startQueued(_ id: UUID, target: String) -> BuildQueue.Start {
        guard let game = library.games.first(where: { $0.id == id }) else { return .skipped(loc.t("queue.gone")) }
        guard !m.running else { return .busy }   // it starts when the running build ends
        let hasFiles = game.inputs[GameLibrary.folderInput]?.isEmpty == false || game.inputs["base", default: []].isEmpty == false
        guard hasFiles else { return .skipped(loc.t("queue.noFiles")) }
        configureBuild(game, fromBatch: true)
        m.target = target
        fillKnownKeys()
        guard m.canBuild else { return .skipped(skipReason) }
        _ = library.rememberInputs(m)
        activeBuildID = game.id   // the queue's game, so its end reaches the queue under this id
        m.startBuild()
        if m.running || !m.staleFrameworks.isEmpty { return .started }
        activeBuildID = nil
        return .skipped(m.doneNote)
    }

    /// A prod.keys another game of the library was built with, that is still there.
    var knownKeys: String? {
        library.games.lazy.compactMap { $0.inputs["keys"]?.first }.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Why a queued game could not start: the input it lacks, else the build's own note.
    private var skipReason: String {
        if m.basePath.isEmpty { return loc.t("queue.noFiles") }
        if m.gameFolder == nil, m.keysPath.isEmpty { return loc.t("queue.noKeys") }
        if !m.doneNote.isEmpty { return m.doneNote }
        return loc.t("queue.noFiles")
    }

    /// The reason a build failed, for the queue: its note, else the failed step's detail or the log's last real line.
    var failureNote: String {
        if !m.doneNote.isEmpty { return m.doneNote }
        let step = m.stages.last { $0.state == .failed }
        let line = BuildProgress.lastMeaningfulLine(m.logTail)
        let detail = step.map(\.detail).flatMap { $0.isEmpty ? nil : $0 } ?? line
        return [step?.name, detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ": ")
    }

    /// The stale frameworks question was answered: Stop ended the queued build before it ran, Continue started it.
    func staleAnswered() {
        DispatchQueue.main.async {
            guard !m.running, let id = queue.building?.id else { return }
            activeBuildID = nil   // the build never ran: the next one is not recorded for this game
            queue.buildEnded(id: id, ok: false, note: loc.t("msg.stopped"))
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
