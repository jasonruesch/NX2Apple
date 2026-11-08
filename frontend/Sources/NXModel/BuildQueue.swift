import Foundation
import Combine
import NXCore

/// Several games built one after another: the player selects them in the library and chooses a target, checks each game's files on
/// the Builds page (`select`), and starts the batch (`startAll`); each builds with the files the library remembers for it. A game that fails, or whose files are gone, does not stop the others. The queue only keeps the
/// order and each game's state; the app sets up and starts each build (`start`) and tells the queue when it ended (`buildEnded`).
@MainActor package final class BuildQueue: ObservableObject {
    package enum State: Equatable {
        case waiting, building, done
        case failed(String)
        /// Not built: the game's files are missing, or the build could not start.
        case skipped(String)
        /// The player stopped the queue before this game.
        case cancelled

        package var isFinished: Bool { self != .waiting && self != .building }
    }

    package struct Entry: Identifiable, Equatable {
        package let id: UUID
        package var name: String
        package var target: String
        package var state: State = .waiting

        package init(id: UUID, name: String, target: String, state: State = .waiting) {
            self.id = id; self.name = name; self.target = target; self.state = state
        }
    }

    /// What `start` says about one game.
    package enum Start: Equatable {
        /// The build runs (or waits on a question the player answers, such as the stale frameworks).
        case started
        /// It could not start, with the reason the queue shows.
        case skipped(String)
        /// Another build runs: the game waits, and the queue tries again when that build ends.
        case busy
    }

    @Published package private(set) var entries: [Entry] = []
    /// The batch runs: games start one after another. Until `startAll`, the games wait for the player to check their files.
    @Published package private(set) var started = false
    /// The game whose files the Builds page shows while the batch is prepared.
    @Published package private(set) var selectedID: UUID?

    /// Sets up the build of the game with this id for this target and starts it.
    package var start: (_ id: UUID, _ target: String) -> Start = { _, _ in .skipped("") }

    package init() {}

    /// A game is building, or more wait in a batch that runs.
    package var isActive: Bool { started && entries.contains { $0.state == .building || $0.state == .waiting } }
    /// Games wait for the player to start the batch.
    package var isPrepared: Bool { !started && entries.contains { $0.state == .waiting } }
    package var waitingCount: Int { entries.filter { $0.state == .waiting }.count }
    package var building: Entry? { entries.first { $0.state == .building } }
    package var finishedCount: Int { entries.filter(\.state.isFinished).count }

    /// Adds the games in this order (one already waiting or building is not added twice). With `start`, the batch runs and the first
    /// game starts if nothing builds; without it, the games wait for `startAll` while the player checks their files.
    package func enqueue(_ games: [(id: UUID, name: String)], target: String, buildRunning: Bool, start: Bool = true) {
        if !isActive { entries.removeAll { $0.state.isFinished } }   // a new batch: the last one's results go
        for game in games where !entries.contains(where: { $0.id == game.id && !$0.state.isFinished }) {
            entries.removeAll { $0.id == game.id }
            entries.append(Entry(id: game.id, name: game.name, target: target))
        }
        if start { startAll(buildRunning: buildRunning) } else if selectedID == nil { selectedID = entries.first { $0.state == .waiting }?.id }
    }

    /// Starts the batch from its first waiting game, whichever game the Builds page shows.
    package func startAll(buildRunning: Bool = false) {
        guard entries.contains(where: { $0.state == .waiting }) else { return }
        started = true
        selectedID = nil
        if !buildRunning { next() }
    }

    /// The game whose files the Builds page shows, while the batch is prepared.
    package func select(_ id: UUID) {
        guard !started, entries.contains(where: { $0.id == id && $0.state == .waiting }) else { return }
        selectedID = id
    }

    /// The target a waiting game builds for (the player changed it while checking its files).
    package func setTarget(_ target: String, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id && $0.state == .waiting }) else { return }
        entries[index].target = target
    }

    /// Takes a waiting game out of the batch.
    package func remove(_ id: UUID) {
        entries.removeAll { $0.id == id && $0.state == .waiting }
        if selectedID == id { selectedID = entries.first { $0.state == .waiting }?.id }
        if !entries.contains(where: { $0.state == .waiting || $0.state == .building }) { started = false }
    }

    /// Starts the first waiting game, skipping each that cannot start, until one runs or none waits.
    package func next() {
        guard started, building == nil else { return }
        defer { if !entries.contains(where: { $0.state == .waiting || $0.state == .building }) { started = false } }
        while let index = entries.firstIndex(where: { $0.state == .waiting }) {
            entries[index].state = .building
            switch start(entries[index].id, entries[index].target) {
            case .started: return
            case .busy: entries[index].state = .waiting; return
            case .skipped(let why): entries[index].state = .skipped(why)
            }
        }
    }

    /// The build of the game `id` ended: done, or failed with the build's note. The next game starts. An end for another game (a
    /// build the player started themselves, or a second report of one that ended already) changes no entry, and only lets a game
    /// that waited for that build start.
    package func buildEnded(id: UUID?, ok: Bool, note: String) {
        if let id, let index = entries.firstIndex(where: { $0.id == id && $0.state == .building }) {
            entries[index].state = ok ? .done : .failed(note)
        }
        next()
    }

    /// The games that wait are not built. The one building is the build's to stop.
    package func cancelWaiting() {
        for index in entries.indices where entries[index].state == .waiting { entries[index].state = .cancelled }
        selectedID = nil
        if building == nil { started = false }
    }

    /// Forgets the games that are finished.
    package func clearFinished() { entries.removeAll { $0.state.isFinished } }
}
