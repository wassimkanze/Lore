import AppKit
import Observation
import Sparkle

/// Sparkle verifies an EdDSA-signed appcast enclosure and the macOS code signature
/// before replacing the installed bundle in place. No custom privileged installer.
@MainActor @Observable final class SparkleUpdateService: NSObject, SPUUpdaterDelegate {
    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private let power: ClosedLidController
    @ObservationIgnored private var started = false

    init(power: ClosedLidController) {
        self.power = power
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    }
    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown" }
    var statusLabel: String {
        #if DEBUG
        "Development build — updates disabled"
        #else
        "Signed updates checked automatically"
        #endif
    }
    var canCheck: Bool { started && controller.updater.canCheckForUpdates }
    func start() {
        #if DEBUG
        return // Never replace an Xcode/test build via a public release feed.
        #endif
        guard !started else { return }
        started = true
        controller.startUpdater()
    }
    func check() {
        guard canCheck else { return }
        controller.checkForUpdates(nil)
    }

    // A closed-lid lease must not be interrupted by an update or relaunch.
    func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem,
                 updateCheck: SPUUpdateCheck, error: AutoreleasingUnsafeMutablePointer<NSError?>) -> Bool {
        guard !power.leaseInUse && !power.restorationPending else {
            error.pointee = NSError(domain: "app.lore.mac.update", code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "Stop closed-lid Pulse and wait for normal sleep before updating Lore."])
            return false
        }
        return true
    }
}
