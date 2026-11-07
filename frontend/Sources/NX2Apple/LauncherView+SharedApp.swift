import SwiftUI
import NXCore
import NXModel

// What the library records when the iPhone app page's job ends: every game in the shared app is installed on the device, or in the
// exported IPA. The page itself is SharedAppPage.swift.

extension LauncherView {
    func recordSharedJob(_ job: SharedJob) {
        switch job {
        case .install:
            library.recordSharedAppInstalled(app: m.installedAppPath, device: m.installedOn)
            readSignatures()
        case .export:
            library.recordSharedExport(m.exportedIPAPath, shellRoot: m.shellRoot)
        case .send:
            break
        }
    }
}
