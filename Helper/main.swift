import Foundation
import Darwin

final class HelperServer: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "app.lore.power-helper.state")
    let engine: ClosedLidLeaseEngine
    private let requirement: String
    private var timer: DispatchSourceTimer?
    private var termination: DispatchSourceSignal?
    init(backend: any ClosedLidBackend, requirement: String) {
        engine = ClosedLidLeaseEngine(backend: backend); self.requirement = requirement
        super.init()
        queue.sync { engine.recover() }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in self?.engine.tick(now: ProcessInfo.processInfo.systemUptime, conditions: ClosedLidEnvironment.read()) }
        timer.resume(); self.timer = timer
        signal(SIGTERM, SIG_IGN)
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        termination.setEventHandler { [weak self] in self?.engine.shutdown(); exit(0) }
        termination.resume(); self.termination = termination
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier >= 500 else { return false }
        connection.setCodeSigningRequirement(requirement)
        let endpoint = ClientEndpoint(server: self)
        connection.exportedInterface = NSXPCInterface(with: PowerHelperProtocol.self)
        connection.exportedObject = endpoint
        connection.invalidationHandler = { [weak self, id = endpoint.id] in
            self?.queue.async { [weak self] in _ = self?.engine.end(owner: id, now: ProcessInfo.processInfo.systemUptime) }
        }
        connection.resume()
        return true
    }
}
final class ClientEndpoint: NSObject, PowerHelperProtocol, @unchecked Sendable {
    let id = UUID().uuidString
    private let server: HelperServer
    init(server: HelperServer) { self.server = server }
    private func respond(_ reply: @escaping @Sendable (Data) -> Void, operation: @escaping @Sendable (ClosedLidLeaseEngine, String, TimeInterval) -> PowerHelperReply) {
        server.queue.async { [self] in
            let value = operation(server.engine, id, ProcessInfo.processInfo.systemUptime)
            reply((try? JSONEncoder().encode(value)) ?? Data())
        }
    }
    func status(reply: @escaping @Sendable (Data) -> Void) { respond(reply) { $0.status(owner: $1, now: $2) } }
    func begin(seconds: Double, reply: @escaping @Sendable (Data) -> Void) {
        respond(reply) { $0.begin(owner: $1, seconds: seconds, now: $2, conditions: ClosedLidEnvironment.read()) }
    }
    func heartbeat(reply: @escaping @Sendable (Data) -> Void) { respond(reply) { $0.heartbeat(owner: $1, now: $2, conditions: ClosedLidEnvironment.read()) } }
    func end(reply: @escaping @Sendable (Data) -> Void) { respond(reply) { $0.end(owner: $1, now: $2) } }
}

@main struct PowerHelperMain {
    static func main() throws {
        guard let team = SignedIdentity.teamID,
              let requirement = SignedIdentity.requirement(identifier: PowerHelperIdentity.appID, team: team) else { exit(EX_CONFIG) }
        if CommandLine.arguments.contains("--validate-signature") { print("Signed helper identity validated."); return }
        guard geteuid() == 0 else { exit(EX_NOPERM) }
        let server = try HelperServer(backend: SystemSleepBackend(), requirement: requirement)
        let listener = NSXPCListener(machServiceName: PowerHelperIdentity.serviceID)
        listener.delegate = server; listener.resume()
        withExtendedLifetime(server) { RunLoop.current.run() }
    }
}
