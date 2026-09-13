import Foundation

public struct LidObservation: Codable, Sendable {
    public private(set) var closedSeconds: Double = 0
    public private(set) var largestGap: Double = 0
    public private(set) var unknownSamples = 0
    public private(set) var reopened = false
    private var lastElapsed: Double?
    private var lastClosed: Bool?
    public init() {}
    public mutating func record(closed: Bool?, elapsed: Double) {
        guard elapsed.isFinite, lastElapsed.map({ elapsed >= $0 }) ?? true else { return }
        if let previous = lastElapsed {
            let gap = elapsed - previous; largestGap = max(largestGap, gap)
            if lastClosed == true { closedSeconds += gap }
        }
        if lastClosed == true && closed == false { reopened = true }
        if closed == nil { unknownSamples += 1 }
        lastElapsed = elapsed; lastClosed = closed
    }
    public var continuousSamplingConfirmed: Bool { reopened && closedSeconds >= 30 && largestGap < 3 && unknownSamples == 0 }
}
