import Foundation
import ServiceManagement
import Observation

@MainActor @Observable public final class ClosedLidController {
    public private(set) var registration = "Not configured"
    public private(set) var message: String?
    public private(set) var isActive = false
    public private(set) var leaseInUse = false
    public private(set) var restorationPending = false
    public private(set) var secondsRemaining: Double = 0
    public private(set) var busy = false
    public private(set) var requiresApproval = false
    public private(set) var isRegistered = false
    public private(set) var statusAvailable = false
    public let signingTeam = SignedIdentity.teamID
    public let isDebugBuild = SignedIdentity.isDebuggable
    @ObservationIgnored private let service = SMAppService.daemon(plistName: PowerHelperIdentity.plistName)
    @ObservationIgnored private var connection: NSXPCConnection?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    public init() {}
    public var canConfigure: Bool { signingTeam != nil && !isDebugBuild }
    public var canStart: Bool { isRegistered && statusAvailable && canConfigure && !busy && !leaseInUse && !restorationPending }
    public func refresh() async {
        requiresApproval = service.status == .requiresApproval
        isRegistered = service.status == .enabled
        switch service.status {
        case .enabled: registration = "Authorized"
        case .requiresApproval: registration = "Waiting for macOS approval"
        case .notRegistered: registration = "Not configured"
        case .notFound: registration = "Power service unavailable"
        @unknown default: registration = "Unavailable"
        }
        if requiresApproval { message = nil }
        if isRegistered {
            do { accept(try await request(.status)) }
            catch { message = "The power service could not be reached. Check its authorization in System Settings."; isActive = false; statusAvailable = false }
        }
    }
    /// Called only by an explicit button in Lore. Approval is performed by macOS.
    public func configure() async {
        guard canConfigure else { message = "Open the installed, signed version of Lore to configure closed-lid access."; return }
        guard !Bundle.main.bundleURL.path.contains("/Build/Products/") else { message = "Install Lore in Applications before configuring its power service."; return }
        busy = true; defer { busy = false }
        do { try service.register(); message = nil }
        catch { message = "macOS could not register the power service. Check Login Items & Extensions." }
        await refresh()
    }
    public func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }
    public func start(seconds: TimeInterval) async {
        guard canStart else { return }
        busy = true; defer { busy = false }
        do {
            let reply = try await request(.begin(seconds)); accept(reply)
            if isActive { startHeartbeat() }
        } catch { message = "The power service did not confirm activation. Closed-lid mode is not confirmed active."; isActive = false; statusAvailable = false }
    }
    public func stop() async {
        busy = true; defer { busy = false }
        heartbeatTask?.cancel(); heartbeatTask = nil
        do { accept(try await request(.end)) }
        catch { isActive = false; statusAvailable = false; restorationPending = true; message = "Connection lost. The power service will restore sleep when its heartbeat expires." }
    }
    public func removeAuthorization() async {
        guard !leaseInUse && !restorationPending else { message = "Wait for normal sleep to be restored before removing authorization."; return }
        busy = true; defer { busy = false }
        do { try await service.unregister(); connection?.invalidate(); connection = nil; message = nil }
        catch { message = "macOS could not remove the service. Review Login Items & Extensions." }
        await refresh()
    }
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { break }
                guard let self else { break }
                do {
                    let reply = try await request(.heartbeat)
                    guard !Task.isCancelled else { break }
                    accept(reply)
                    if !isActive { break }
                } catch {
                    isActive = false; statusAvailable = false; restorationPending = true; message = "Connection interrupted. The service restores normal sleep if Lore stops responding."; break
                }
            }
        }
    }
    private func accept(_ reply: PowerHelperReply) {
        statusAvailable = reply.sleepDisabled != nil
        restorationPending = reply.restorationPending
        leaseInUse = reply.leaseActive
        isActive = reply.leaseActive && reply.ownedByClient && reply.sleepDisabled == true
        secondsRemaining = reply.secondsRemaining; message = reply.message
        if !reply.ownedByClient && reply.sleepDisabled == true { message = reply.message ?? "System sleep is controlled by another session or utility." }
    }
    private enum Operation { case status, begin(Double), heartbeat, end }
    private func request(_ operation: Operation) async throws -> PowerHelperReply {
        guard let signingTeam, let requirement = SignedIdentity.requirement(identifier: PowerHelperIdentity.serviceID, team: signingTeam) else { throw CocoaError(.executableNotLoadable) }
        let connection: NSXPCConnection
        if let existing = self.connection { connection = existing }
        else {
            connection = NSXPCConnection(machServiceName: PowerHelperIdentity.serviceID, options: .privileged)
            connection.remoteObjectInterface = NSXPCInterface(with: PowerHelperProtocol.self)
            connection.setCodeSigningRequirement(requirement)
            let connectionID = ObjectIdentifier(connection)
            let invalidated: @Sendable () -> Void = { [weak self] in
                Task { @MainActor in
                    guard let current = self?.connection, ObjectIdentifier(current) == connectionID else { return }
                    self?.connection = nil
                }
            }
            connection.invalidationHandler = invalidated
            connection.resume(); self.connection = connection
        }
        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, any Error>) in
            let gate = PowerReplyGate(continuation)
            // NSXPC invokes this on its own queue. Explicit Sendable prevents an
            // inferred MainActor callback (and a runtime isolation trap on error).
            guard let proxy = connection.remoteObjectProxyWithErrorHandler(gate.errorHandler) as? PowerHelperProtocol else {
                gate.finish(.failure(CocoaError(.executableNotLoadable))); return
            }
            let reply: @Sendable (Data) -> Void = { gate.finish(.success($0)) }
            switch operation {
            case .status: proxy.status(reply: reply)
            case .begin(let seconds): proxy.begin(seconds: seconds, reply: reply)
            case .heartbeat: proxy.heartbeat(reply: reply)
            case .end: proxy.end(reply: reply)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 8) { gate.finish(.failure(CocoaError(.executableLoad))) }
        }
        guard data.count < 16_384 else { throw CocoaError(.coderReadCorrupt) }
        return try JSONDecoder().decode(PowerHelperReply.self, from: data)
    }
}
