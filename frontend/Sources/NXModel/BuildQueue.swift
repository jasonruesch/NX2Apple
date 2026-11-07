import Foundation
import Combine
import NXCore

/// Several games built one after another: the player selects them in the library and chooses a target, and each builds with the files
/// the library remembers for it. A game that fails, or whose files are gone, does not stop the others. The queue only keeps the
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
    }

    @Published package private(set) var entries: [Entry] = []

    /// Sets up the build of the game with this id for this target and starts it.
    package var start: (_ id: UUID, _ target: String) -> Start = { _, _ in .skipped("") }

    package init() {}

    /// A game is building, or more wait.
    package var isActive: Bool { entries.contains { $0.state == .building || $0.state == .waiting } }
    package var building: Entry? { entries.first { $0.state == .building } }
    package var finishedCount: Int { entries.filter(\.state.isFinished).count }

    /// Adds the games in this order (one already waiting or building is not added twice), then starts the first if nothing builds.
    package func enqueue(_ games: [(id: UUID, name: String)], target: String, buildRunning: Bool) {
        for game in games where !entries.contains(where: { $0.id == game.id && !$0.state.isFinished }) {
            entries.removeAll { $0.id == game.id }
            entries.append(Entry(id: game.id, name: game.name, target: target))
        }
        if !buildRunning { next() }
    }

    /// Starts the first waiting game, skipping each that cannot start, until one runs or none waits.
    package func next() {
        guard building == nil else { return }
        while let index = entries.firstIndex(where: { $0.state == .waiting }) {
            entries[index].state = .building
            switch start(entries[index].id, entries[index].target) {
            case .started: return
            case .skipped(let why): entries[index].state = .skipped(why)
            }
        }
    }

    /// The building game's build ended: done, or failed with the build's note. The next game starts.
    package func buildEnded(ok: Bool, note: String) {
        guard let index = entries.firstIndex(where: { $0.state == .building }) else { return }
        entries[index].state = ok ? .done : .failed(note)
        next()
    }

    /// The games that wait are not built. The one building is the build's to stop.
    package func cancelWaiting() {
        for index in entries.indices where entries[index].state == .waiting { entries[index].state = .cancelled }
    }

    /// Forgets the games that are finished.
    package func clearFinished() { entries.removeAll { $0.state.isFinished } }
}
