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
        queue.clearFinished()
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
}
