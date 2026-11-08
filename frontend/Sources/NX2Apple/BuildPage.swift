import SwiftUI
import NXCore
import NXLauncher
import NXModel

// The Builds page: the cards in the order a build goes, from the files to the progress. It only arranges them (CardPages.swift
// scrolls them). Each card observes the stores it shows (NXLauncher, and `FilesCard` here), so a change in one store redraws that
// card and no other.

struct BuildPage: View {
    let build: BuildStore
    let running: Bool
    let repo: RepoStore
    let dependencies: DependencyStore
    let devices: DeviceStore
    @Binding var extrasOpen: Bool   // the optional input rows of the files card
    @Binding var logOpen: Bool   // the log card's disclosure
    var queue: BuildQueue?   // the batch the library sent (QueueCard)
    var onShowQueued: (UUID) -> Void = { _ in }   // shows a batch game's files in the cards (LauncherView+Queue.swift)
    var onStartQueue: () -> Void = {}   // the Build games button
    var onBuildQueued: (UUID) -> Void = { _ in }   // builds one batch game on its own
    @State private var showRunningSetup = false
    var onViewGame: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onOpenSharedApp: () -> Void = {}
    @EnvironmentObject var loc: Localizer

    var body: some View {
        CardPageHeading(loc.t("build.heading"), note: loc.t(running ? (build.target == BuildTarget.mac ? "activity.mac" : "activity.ios") : "build.intro"))
        if let queue { QueueCard(queue: queue, onSelect: onShowQueued, onBuildOne: onBuildQueued) }
        if running {
            ProgressCard(build: build)
            CardDisclosure(loc.t("section.setup"), detail: build.gameName, isOpen: showRunningSetup) { showRunningSetup.toggle() }
                .accessibilityLabel(loc.t("section.setup"))
                .accessibilityValue([build.gameName, loc.t(showRunningSetup ? "onboarding.expanded" : "onboarding.collapsed")]
                    .filter { !$0.isEmpty }.joined(separator: ", "))
                .onDisappear { showRunningSetup = false }
        }
        if !running || showRunningSetup {
            SetupHintCard(repo: repo, dependencies: dependencies, onOpenSettings: onOpenSettings)
            FilesCard(build: build, extrasOpen: $extrasOpen)
            TargetCard(build: build)
        }
        InstallCard(devices: devices, build: build, showLocked: showRunningSetup, onOpenSharedApp: onOpenSharedApp)
        LogCard(log: build.log, devices: devices, isOpen: $logOpen,
                showRequests: BuildNotifier.shared.$showLog.eraseToAnyPublisher(),   // a clicked notification of a failed build
                didShow: { BuildNotifier.shared.showLog = false })
        if let queue {
            ActionCard(build: build, dependencies: dependencies, repo: repo, queue: queue, onStartQueue: onStartQueue)
        } else {
            ActionCard(build: build, dependencies: dependencies, repo: repo)
        }
        Group {   // a ViewBuilder holds ten views at most
            ShellCopyCard(devices: devices)
            BuildFailureCard(m: build)
            OutcomeCard(build: build, devices: devices, onViewGame: onViewGame, onOpenSharedApp: onOpenSharedApp)
            if !running { ProgressCard(build: build) }
        }
    }
}
