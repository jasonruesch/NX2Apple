import XCTest
@testable import NXModel

/// Games picked in the library build one after another; one that cannot start or fails does not stop the rest.
@MainActor final class BuildQueueTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()

    func testGamesBuildInOrderAndAFailureDoesNotStopTheRest() {
        let queue = BuildQueue()
        var started: [UUID] = []
        queue.start = { id, target in
            XCTAssertEqual(target, "ios")
            started.append(id)
            return id == self.b ? .skipped("no files") : .started
        }
        queue.enqueue([(a, "A"), (b, "B"), (c, "C")], target: "ios", buildRunning: false)
        XCTAssertEqual(started, [a])
        XCTAssertEqual(queue.building?.id, a)
        queue.buildEnded(id: a, ok: false, note: "broke")
        XCTAssertEqual(started, [a, b, c], "B could not start, so C did")
        XCTAssertEqual(queue.entries.map(\.state), [.failed("broke"), .skipped("no files"), .building])
        queue.buildEnded(id: c, ok: true, note: "")
        XCTAssertFalse(queue.isActive)
        XCTAssertEqual(queue.finishedCount, 3)
        queue.clear()
        XCTAssertTrue(queue.entries.isEmpty)
    }

    func testABuildThatRunsWaitsAndCancelledGamesDoNotStart() {
        let queue = BuildQueue()
        var started: [UUID] = []
        queue.start = { id, _ in started.append(id); return .started }
        queue.enqueue([(a, "A"), (b, "B")], target: "mac-app", buildRunning: true)
        XCTAssertTrue(started.isEmpty, "another build runs: the queue waits for it")
        queue.next()
        XCTAssertEqual(started, [a])
        queue.enqueue([(a, "A")], target: "mac-app", buildRunning: true)
        XCTAssertEqual(queue.entries.count, 2, "a game that waits or builds is not added twice")
        queue.cancelWaiting()
        queue.buildEnded(id: a, ok: true, note: "")
        XCTAssertEqual(started, [a])
        XCTAssertEqual(queue.entries.map(\.state), [.done, .cancelled])
    }

    func testAnEndWithNothingBuildingChangesNothing() {
        let queue = BuildQueue()
        queue.buildEnded(id: nil, ok: true, note: "")
        XCTAssertTrue(queue.entries.isEmpty)
    }

    /// A build's end reported twice (the launcher sees "not running" more than once as a build ends) used to fail the game the
    /// first report had just started, with an empty note, and every game after it was skipped as "another build was running".
    func testASecondReportOfTheSameEndDoesNotFailTheNextGame() {
        let queue = BuildQueue()
        var running = false
        var started: [UUID] = []
        queue.start = { id, _ in
            if running { return .busy }
            started.append(id); running = true; return .started
        }
        queue.enqueue([(a, "A"), (b, "B"), (c, "C")], target: "ios", buildRunning: false)
        running = false
        queue.buildEnded(id: a, ok: false, note: "broke")   // A's end: B starts
        queue.buildEnded(id: a, ok: false, note: "")        // the same end again, while B builds
        XCTAssertEqual(queue.entries.map(\.state), [.failed("broke"), .building, .waiting])
        XCTAssertEqual(started, [a, b])
    }

    /// A game that finds another build running (one the player started, or the iPhone app page's) waits for it instead of being skipped.
    func testAGameWaitsWhileAnotherBuildRunsAndStartsWhenItEnds() {
        let queue = BuildQueue()
        var running = true
        queue.start = { _, _ in running ? .busy : .started }
        queue.enqueue([(a, "A"), (b, "B")], target: "ios", buildRunning: false)
        XCTAssertEqual(queue.entries.map(\.state), [.waiting, .waiting])
        running = false
        queue.buildEnded(id: nil, ok: true, note: "")   // the other build ended: not one of the queue's
        XCTAssertEqual(queue.entries.map(\.state), [.building, .waiting])
    }

    /// Picked games wait while the player checks each one's files; Build games starts the batch from the first game, whichever one
    /// the page shows.
    func testAPreparedBatchWaitsAndStartsFromTheFirstGame() {
        let queue = BuildQueue()
        var started: [(UUID, String)] = []
        queue.start = { id, target in started.append((id, target)); return .started }
        queue.enqueue([(a, "A"), (b, "B"), (c, "C")], target: "ios", buildRunning: false, start: false)
        XCTAssertTrue(started.isEmpty, "nothing builds before Build games")
        XCTAssertTrue(queue.isPrepared)
        XCTAssertFalse(queue.isActive)
        XCTAssertEqual(queue.selectedID, a, "the first game's files are shown")
        queue.select(c)
        queue.setTarget("mac-app", for: c)
        queue.remove(b)
        queue.buildEnded(id: nil, ok: true, note: "")   // another build ended: the prepared batch still waits
        XCTAssertTrue(started.isEmpty)
        XCTAssertEqual(queue.waitingCount, 2)

        queue.startAll()
        XCTAssertEqual(started.map(\.0), [a], "the first game, though C was shown")
        XCTAssertNil(queue.selectedID)
        XCTAssertTrue(queue.isActive)
        queue.buildEnded(id: a, ok: true, note: "")
        XCTAssertEqual(started.map(\.0), [a, c])
        XCTAssertEqual(started.last?.1, "mac-app", "the target set while its files were shown")
        queue.buildEnded(id: c, ok: true, note: "")
        XCTAssertFalse(queue.started, "the batch has finished")
        XCTAssertTrue(queue.isPrepared, "it stays, with each game's result, to be changed and built again")
        XCTAssertTrue(queue.hasResults)
    }

    /// After a run, a failed game can be shown, built on its own, and the whole batch built again.
    func testAFinishedBatchCanBuildOneGameAgainOrAllOfThem() {
        let queue = BuildQueue()
        var started: [UUID] = []
        queue.start = { id, _ in started.append(id); return .started }
        queue.enqueue([(a, "A"), (b, "B")], target: "ios", buildRunning: false)
        queue.buildEnded(id: a, ok: true, note: "")
        queue.buildEnded(id: b, ok: false, note: "wrong file")
        XCTAssertEqual(queue.entries.map(\.state), [.done, .failed("wrong file")])

        queue.select(b)
        XCTAssertEqual(queue.selectedID, b)
        queue.runOne(b)
        XCTAssertEqual(started, [a, b, b])
        XCTAssertEqual(queue.entries.map(\.state), [.done, .building], "A keeps its result")
        XCTAssertFalse(queue.isPrepared, "nothing else starts while it builds")
        queue.buildEnded(id: b, ok: true, note: "")
        XCTAssertEqual(queue.entries.map(\.state), [.done, .done])
        XCTAssertEqual(started.count, 3, "a single build does not start the others")

        queue.startAll()
        XCTAssertEqual(started.last, a, "Rebuild games starts from the first")
        XCTAssertEqual(queue.entries.map(\.state), [.building, .waiting])
        queue.buildEnded(id: a, ok: true, note: "")
        queue.buildEnded(id: b, ok: true, note: "")
        queue.clear()
        XCTAssertTrue(queue.entries.isEmpty)
        XCTAssertFalse(queue.isPrepared)
    }

    /// A single build that finds another build running leaves the game as it was.
    func testASingleBuildWhileAnotherRunsChangesNothing() {
        let queue = BuildQueue()
        queue.start = { _, _ in .started }
        queue.enqueue([(a, "A")], target: "ios", buildRunning: false)
        queue.buildEnded(id: a, ok: false, note: "x")
        queue.start = { _, _ in .busy }
        queue.runOne(a)
        XCTAssertEqual(queue.entries.first?.state, .failed("x"))
    }

    /// One game built from the library sets a waiting batch aside; it comes back with its results, and building it shows it again.
    func testASingleBuildFromTheLibrarySetsAWaitingBatchAside() {
        let queue = BuildQueue()
        queue.start = { _, _ in .started }
        queue.enqueue([(a, "A"), (b, "B")], target: "ios", buildRunning: false, start: false)
        XCTAssertTrue(queue.isShown)
        queue.stepAside()
        XCTAssertFalse(queue.isShown, "the Builds page shows the one game")
        XCTAssertTrue(queue.isPrepared, "the batch is still there")
        queue.bringBack()
        XCTAssertTrue(queue.isShown)

        queue.startAll()
        queue.stepAside()
        XCTAssertTrue(queue.isShown, "a running batch is never set aside")
        queue.buildEnded(id: a, ok: true, note: "")
        queue.buildEnded(id: b, ok: true, note: "")
        queue.stepAside()
        queue.runOne(a)
        XCTAssertTrue(queue.isShown, "building a game of the batch brings it back")
        queue.enqueue([(c, "C")], target: "ios", buildRunning: true, start: false)
        XCTAssertTrue(queue.isShown)
    }
}
