import XCTest
import SwiftUI
import AppKit
@testable import NX2Apple
import NXCore
@testable import NXModel
@testable import NXLauncher

/// Visual QA of the build queue card: a batch whose first game failed and whose second was built, so each finished row shows Remove.
final class BuildQueueCaptureTests: IsolatedDefaultsTestCase {
    @MainActor func testRenderFinishedQueueForVisualQA() throws {
        guard let directory = ProcessInfo.processInfo.environment["NX_LAUNCHER_CAPTURE_DIR"] else { throw XCTSkip("Set NX_LAUNCHER_CAPTURE_DIR to capture native views") }
        let output = URL(fileURLWithPath: directory)
        let fm = FileManager.default
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        let lang = ProcessInfo.processInfo.environment["NX_CAPTURE_LANG"].flatMap { Lang.find($0) } ?? .en
        let folder = fm.temporaryDirectory.appendingPathComponent("NX2Apple-queue-capture-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: folder) }

        var busy = false
        let queue = BuildQueueStore(file: folder.appendingPathComponent("queue.json"), engineID: { "release-1" }, busy: { busy },
                                    start: { _ in busy = true; return nil })
        let batch = UUID()
        queue.enqueue([("01006F8002326000", "Animal Crossing New Horizons", ["base", "update", "dlc"]),
                       ("010093801237C000", "Metroid Dread", ["base"])].map { titleID, name, rows in
            QueueEntry(titleID: titleID, name: name, target: BuildTarget.ios,
                       inputs: Dictionary(uniqueKeysWithValues: rows.map { ($0, ["/Games/\(name) [\(titleID)][\($0)].nsp"]) }),
                       outputDirectory: "/Games", engineID: "release-1", batch: batch, packageAfter: false)
        })
        busy = false; queue.buildEnded(succeeded: false)   // Animal Crossing failed
        busy = false; queue.buildEnded(succeeded: true)    // Metroid Dread was built

        let localizer = Localizer(lang)
        let card = BuildQueueCard(queue: queue, onSelectGames: {})
        let framed = card.environmentObject(localizer).padding(24).frame(width: 760).background(Color(white: 0.09)).environment(\.colorScheme, .dark)
        NSApplication.shared.setActivationPolicy(.accessory)
        let host = NSHostingView(rootView: framed)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor(white: 0.09, alpha: 1).cgColor
        let window = OffscreenWindow(size: host.frame.size)
        window.contentView = host
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("queue-finished-\(lang.code).png"))
        window.orderOut(nil)
    }
}
