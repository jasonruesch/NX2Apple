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
        queue.buildEnded(ok: false, note: "broke")
        XCTAssertEqual(started, [a, b, c], "B could not start, so C did")
        XCTAssertEqual(queue.entries.map(\.state), [.failed("broke"), .skipped("no files"), .building])
        queue.buildEnded(ok: true, note: "")
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
        queue.buildEnded(ok: true, note: "")
        XCTAssertEqual(started, [a])
        XCTAssertEqual(queue.entries.map(\.state), [.done, .cancelled])
    }

    func testAnEndWithNothingBuildingChangesNothing() {
        let queue = BuildQueue()
        queue.buildEnded(ok: true, note: "")
        XCTAssertTrue(queue.entries.isEmpty)
    }
}
