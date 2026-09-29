import Foundation

/// Formatting for the app's debug log (Settings → Debug log), kept here so
/// it can be tested without a phone.
public enum DebugFormat {
    /// "23 00 2C 01": raw packet bytes, as sent by the sensor.
    public static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { byte in
            let digits = String(byte, radix: 16, uppercase: true)
            return byte < 0x10 ? "0" + digits : digits
        }.joined(separator: " ")
    }

    /// "flags=0x0023 power=300W balance=50.0%L crank=258/1024": the decoded
    /// fields, so a log line shows both what arrived and how it was read.
    public static func describe(_ m: CyclingPowerMeasurement) -> String {
        var parts = ["flags=0x" + hex16(m.flags.rawValue), "power=\(m.instantaneousPower)W"]
        if let balance = m.pedalPowerBalance {
            let reference = m.flags.contains(.pedalPowerBalanceReferenceLeft) ? "L" : "?"
            parts.append("balance=\(fixed(balance, 1))%\(reference)")
        }
        if let crank = m.crank {
            parts.append("crank=\(crank.cumulativeRevolutions)/\(crank.lastEventTime)")
        } else {
            parts.append("crank=none")
        }
        return parts.joined(separator: " ")
    }

    /// "14:03:07.250 [power] message", time of day in `timeZone`.
    public static func line(date: Date, category: String, message: String,
                            timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        let seconds = date.timeIntervalSince1970
        let millis = min(999, Int(((seconds - seconds.rounded(.down)) * 1000).rounded(.down)))
        let time = pad(c.hour ?? 0, 2) + ":" + pad(c.minute ?? 0, 2) + ":" + pad(c.second ?? 0, 2)
            + "." + pad(millis, 3)
        return "\(time) [\(category)] \(message)"
    }

    /// Fixed decimal places, "--" for nil. Locale-independent.
    public static func fixed(_ value: Double?, _ places: Int) -> String {
        guard let value, value.isFinite else { return "--" }
        return String(format: "%.\(places)f", value)
    }

    private static func hex16(_ value: UInt16) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}

/// The most recent `capacity` log lines, oldest first, for the on-screen log.
public struct LogRing: Sendable {
    public let capacity: Int
    private var storage: [String] = []

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public var lines: [String] { Array(storage.suffix(capacity)) }

    public mutating func append(_ line: String) {
        storage.append(line)
        // Trim in batches so appends stay cheap.
        if storage.count >= capacity + capacity / 4 + 1 {
            storage.removeFirst(storage.count - capacity)
        }
    }

    public mutating func removeAll() { storage.removeAll() }
}
