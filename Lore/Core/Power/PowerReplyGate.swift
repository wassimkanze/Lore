import Foundation
import OSLog

/// XPC callbacks arrive on arbitrary queues and may race with a timeout.
/// Keep them nonisolated and resume the awaiting task exactly once.
final class PowerReplyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, any Error>?
    init(_ continuation: CheckedContinuation<Data, any Error>) { self.continuation = continuation }
    func finish(_ result: Result<Data, any Error>) {
        lock.lock(); let value = continuation; continuation = nil; lock.unlock()
        value?.resume(with: result)
    }
    var errorHandler: @Sendable (any Error) -> Void {
        { [self] error in
            let code = error as NSError
            Logger(subsystem: "app.lore.mac", category: "PowerService").error("XPC request failed: \(code.domain, privacy: .public) \(code.code)")
            finish(.failure(error))
        }
    }
}
