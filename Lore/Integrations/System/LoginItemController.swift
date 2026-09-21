import Foundation
import Observation
import ServiceManagement

@MainActor @Observable final class LoginItemController {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var errorMessage: String?
    private(set) var isBusy = false

    init() { refresh() }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var requiresApproval: Bool { status == .requiresApproval }
    var statusLabel: String {
        switch status {
        case .enabled: "Starts automatically"
        case .requiresApproval: "Approval required in System Settings"
        case .notRegistered: "Starts manually"
        case .notFound: "Unavailable for this copy of Lore"
        @unknown default: "Status unavailable"
        }
    }

    func refresh() {
        Task { [weak self] in
            let rawStatus = await Task.detached { SMAppService.mainApp.status.rawValue }.value
            guard let self else { return }
            status = SMAppService.Status(rawValue: rawStatus) ?? .notFound
            if status != .notFound { errorMessage = nil }
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        Task { [weak self] in
            let outcome = await Task.detached { () -> (Int, Bool) in
                let service = SMAppService.mainApp
                do {
                    if enabled {
                        if service.status == .notRegistered { try service.register() }
                    } else if service.status != .notRegistered {
                        try service.unregister()
                    }
                    return (service.status.rawValue, false)
                } catch {
                    return (service.status.rawValue, true)
                }
            }.value
            guard let self else { return }
            status = SMAppService.Status(rawValue: outcome.0) ?? .notFound
            isBusy = false
            if outcome.1 {
                errorMessage = enabled
                    ? "Lore couldn’t add itself to Login Items. You can allow it in System Settings."
                    : "Lore couldn’t remove itself from Login Items. Review it in System Settings."
            }
        }
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
