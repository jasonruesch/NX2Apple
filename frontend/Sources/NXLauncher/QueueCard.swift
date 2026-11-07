import SwiftUI
import NXCore
import NXModel

/// The batch of games the library sent to the Builds page: each game's state, Stop for the games that wait, Clear for the finished.
/// Observes the queue only.
package struct QueueCard: View {
    @ObservedObject var queue: BuildQueue
    @EnvironmentObject var loc: Localizer

    package init(queue: BuildQueue) { self.queue = queue }

    package var body: some View {
        if !queue.entries.isEmpty {
            CardGroup(String(format: loc.t("queue.section"), queue.finishedCount, queue.entries.count)) {
                ForEach(Array(queue.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { CardDivider() }
                    CardRow(entry.name, detail: detail(entry), dot: dot(entry.state)) { EmptyView() }
                }
                CardDivider()
                CardRow(queue.isActive ? loc.t("queue.running") : loc.t("queue.finished")) {
                    if queue.entries.contains(where: { $0.state == .waiting }) {
                        Button(loc.t("queue.cancel")) { queue.cancelWaiting() }
                    }
                    if !queue.isActive { Button(loc.t("queue.clear")) { queue.clearFinished() } }
                }
            }
        }
    }

    private func detail(_ entry: BuildQueue.Entry) -> String {
        let target = loc.t(entry.target == BuildTarget.mac ? "build.mac" : "build.ios")
        let state: String
        switch entry.state {
        case .waiting: state = loc.t("queue.waiting")
        case .building: state = loc.t("library.building")
        case .done: state = loc.t("queue.done")
        case .failed(let why): state = why.isEmpty ? loc.t("queue.failed") : why
        case .skipped(let why): state = why.isEmpty ? loc.t("queue.skipped") : why
        case .cancelled: state = loc.t("queue.cancelled")
        }
        return target + " · " + state
    }

    private func dot(_ state: BuildQueue.State) -> Color? {
        switch state {
        case .waiting, .cancelled: return nil
        case .building: return LauncherPalette.building
        case .done: return LauncherPalette.ready
        case .failed, .skipped: return LauncherPalette.danger
        }
    }
}
