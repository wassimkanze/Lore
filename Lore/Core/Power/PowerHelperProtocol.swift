import Foundation

public enum PowerHelperIdentity {
    public static let appID = "app.lore.mac"
    public static let serviceID = "app.lore.power-helper"
    public static let plistName = "app.lore.power-helper.plist"
}

@objc(LorePowerHelperProtocol) public protocol PowerHelperProtocol {
    func status(reply: @escaping @Sendable (Data) -> Void)
    func begin(seconds: Double, reply: @escaping @Sendable (Data) -> Void)
    func heartbeat(reply: @escaping @Sendable (Data) -> Void)
    func end(reply: @escaping @Sendable (Data) -> Void)
}

public struct PowerHelperReply: Codable, Sendable {
    public var sleepDisabled: Bool?
    public var leaseActive: Bool
    public var ownedByClient: Bool
    public var secondsRemaining: Double
    public var restorationPending: Bool
    public var message: String?
    public init(sleepDisabled: Bool?, leaseActive: Bool, ownedByClient: Bool, secondsRemaining: Double = 0, message: String? = nil, restorationPending: Bool = false) {
        self.sleepDisabled = sleepDisabled; self.leaseActive = leaseActive; self.ownedByClient = ownedByClient
        self.secondsRemaining = secondsRemaining; self.message = message; self.restorationPending = restorationPending
    }
}
