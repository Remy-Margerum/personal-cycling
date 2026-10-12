import Foundation

/// ActiveLook head-up display glasses (ENGO 2 and others): the BLE command
/// protocol, and the cycling dashboard drawn with the layouts preloaded in
/// the glasses' "ALooK" configuration, so no fonts or images are uploaded.
///
/// Protocol: github.com/ActiveLook/Activelook-API-Documentation
/// Layouts and positions: github.com/ActiveLook/Activelook-Visual-Assets
public enum ActiveLook {
    public static let commandService = "0783B03E-8535-B5A0-7140-A304D2495CB7"
    /// Notify: responses to commands.
    public static let txCharacteristic = "0783B03E-8535-B5A0-7140-A304D2495CB8"
    /// Notify: flow control and errors (see `ControlSignal`).
    public static let controlCharacteristic = "0783B03E-8535-B5A0-7140-A304D2495CB9"
    /// Write: commands.
    public static let rxCharacteristic = "0783B03E-8535-B5A0-7140-A304D2495CBA"
    /// Notify: a tap on the glasses' touch sensor.
    public static let touchCharacteristic = "0783B03E-8535-B5A0-7140-A304D2495CBC"
    /// The firmware-update service UUID, the only one in the advertisement.
    public static let advertisedService = "FEF5"
    /// The built-in configuration holding the default fonts, icons and layouts.
    public static let defaultConfiguration = "ALooK"

    /// True for an advertisement from ActiveLook glasses: manufacturer data
    /// ending in the ActiveLook marker 0x08F2 (after the brand's company ID),
    /// or failing that a known name ("ENGO 2…", "engo3…", "A.Look…").
    public static func isActiveLook(manufacturerData: [UInt8], name: String? = nil) -> Bool {
        if manufacturerData.count >= 4 && Array(manufacturerData.suffix(2)) == [0x08, 0xF2] { return true }
        let lowercased = name?.lowercased() ?? ""
        return lowercased.hasPrefix("engo") || lowercased.hasPrefix("a.look")
    }

    // MARK: Commands

    public enum Command: Equatable, Sendable {
        /// Black screen.
        case clear
        /// Firmware version; answered with `Response.version`.
        case version
        /// Battery level; answered with id 0x05.
        case battery
        /// Write text with a built-in font (0-3) and grey level (0-15).
        case text(x: Int16, y: Int16, rotation: UInt8, font: UInt8, grey: UInt8, String)
        /// Select the configuration whose layouts and fonts later commands use.
        case configurationSet(String)
        /// How many layouts, images, … a configuration holds; answered with id 0xD1.
        case configurationRead(String)
        /// Clear a saved layout's area at (x, y) and draw `text` in it.
        case layoutClearAndDisplay(id: UInt8, x: UInt16, y: UInt8, text: String)

        public var id: UInt8 {
            switch self {
            case .clear: 0x01
            case .version: 0x06
            case .battery: 0x05
            case .text: 0x37
            case .configurationSet: 0xD2
            case .configurationRead: 0xD1
            case .layoutClearAndDisplay: 0x6A
            }
        }

        var data: [UInt8] {
            switch self {
            case .clear, .version, .battery:
                []
            case let .text(x, y, rotation, font, grey, string):
                bytes(x) + bytes(y) + [rotation, font, grey] + cString(string)
            case let .configurationSet(name), let .configurationRead(name):
                cString(String(name.prefix(11)))
            case let .layoutClearAndDisplay(id, x, y, text):
                [id] + bytes(x) + [y] + cString(text)
            }
        }

        /// The whole command: 0xFF, id, format, length, data, 0xAA. Lengths
        /// over 255 bytes switch to the two-byte length format.
        public var frame: [UInt8] {
            let payload = data
            let short = 5 + payload.count
            if short <= 0xFF {
                return [0xFF, id, 0x00, UInt8(short)] + payload + [0xAA]
            }
            let long = UInt16(6 + payload.count)
            return [0xFF, id, 0x10] + bytes(long) + payload + [0xAA]
        }
    }

    // MARK: Responses

    public struct Response: Equatable, Sendable {
        public let id: UInt8
        public let data: [UInt8]

        public init(id: UInt8, data: [UInt8]) {
            self.id = id
            self.data = data
        }

        /// "4.11.2b" from a `version` response.
        public var version: String? {
            guard id == 0x06, data.count >= 4 else { return nil }
            let suffix = (0x61...0x7A).contains(data[3]) ? String(UnicodeScalar(data[3])) : ""
            return "\(data[0]).\(data[1]).\(data[2])\(suffix)"
        }

        /// Battery percentage from a `battery` response.
        public var batteryLevel: Int? {
            id == 0x05 && data.count == 1 && data[0] <= 100 ? Int(data[0]) : nil
        }

        /// Number of layouts in a `configurationRead` response.
        public var configurationLayoutCount: Int? {
            id == 0xD1 && data.count >= 9 ? Int(data[5]) : nil
        }

        /// (failed command id, error code) from an asynchronous error report.
        public var error: (command: UInt8, code: UInt8)? {
            id == 0xE2 && data.count >= 2 ? (data[0], data[1]) : nil
        }
    }

    /// Reassembles responses from TX notifications, which may split or join
    /// frames, and skips bytes that don't form a valid frame.
    public struct ResponseReader: Sendable {
        private var buffer: [UInt8] = []

        public init() {}

        public mutating func append(_ bytes: [UInt8]) -> [Response] {
            buffer += bytes
            var responses: [Response] = []
            while let start = buffer.firstIndex(of: 0xFF) {
                buffer.removeFirst(start)
                guard buffer.count >= 4 else { break }
                let longLength = buffer[2] & 0x10 != 0
                let header = 3 + (longLength ? 2 : 1) + Int(buffer[2] & 0x0F)
                guard buffer.count >= (longLength ? 5 : 4) else { break }
                let length = longLength ? Int(buffer[3]) << 8 | Int(buffer[4]) : Int(buffer[3])
                guard length > header else {
                    buffer.removeFirst()
                    continue
                }
                guard buffer.count >= length else { break }
                if buffer[length - 1] == 0xAA {
                    responses.append(Response(id: buffer[1], data: Array(buffer[header ..< length - 1])))
                    buffer.removeFirst(length)
                } else {
                    buffer.removeFirst()
                }
            }
            if buffer.first != 0xFF { buffer.removeAll() }
            return responses
        }
    }

    /// Values notified on the control characteristic.
    public enum ControlSignal: Equatable, Sendable {
        /// The glasses can take more data.
        case resume
        /// Their buffer is 75% full: stop sending until `resume`.
        case pause
        case error(UInt8)

        public init?(_ bytes: [UInt8]) {
            guard let value = bytes.first else { return nil }
            switch value {
            case 0x01: self = .resume
            case 0x02: self = .pause
            default: self = .error(value)
            }
        }
    }

    // MARK: Sending

    /// Commands waiting for the glasses, sent one BLE write at a time. A
    /// command queued under a key that's already waiting replaces it in
    /// place, so on a slow link stale dashboard values are dropped instead
    /// of piling up.
    public struct CommandQueue: Sendable {
        private struct Entry: Sendable {
            let key: String?
            var frame: [UInt8]
        }

        private var entries: [Entry] = []
        private var chunks: [[UInt8]] = []
        public private(set) var waitingForAcknowledgement = false

        public init() {}

        public var isEmpty: Bool { entries.isEmpty && chunks.isEmpty }

        public mutating func enqueue(_ command: Command, key: String? = nil) {
            if let key, let index = entries.firstIndex(where: { $0.key == key }) {
                entries[index].frame = command.frame
            } else {
                entries.append(Entry(key: key, frame: command.frame))
            }
        }

        /// The next chunk (at most `maxLength` bytes) to write, or nil when
        /// there's nothing to send or the previous write isn't acknowledged.
        public mutating func nextWrite(maxLength: Int) -> [UInt8]? {
            guard !waitingForAcknowledgement else { return nil }
            if chunks.isEmpty {
                guard !entries.isEmpty else { return nil }
                let frame = entries.removeFirst().frame
                let size = max(1, maxLength)
                chunks = stride(from: 0, to: frame.count, by: size).map {
                    Array(frame[$0 ..< min($0 + size, frame.count)])
                }
            }
            waitingForAcknowledgement = true
            return chunks.removeFirst()
        }

        public mutating func acknowledged() { waitingForAcknowledgement = false }

        public mutating func removeAll() {
            entries = []
            chunks = []
            waitingForAcknowledgement = false
        }
    }
}

// MARK: Dashboard

/// What the glasses show.
public struct GlassesMetrics: Equatable, Sendable {
    public var power3s: Double?
    public var heartRate: Int?
    /// m/s
    public var speed: Double?
    public var cadence: Double?
    public var metric: Bool

    public init(power3s: Double? = nil, heartRate: Int? = nil, speed: Double? = nil,
                cadence: Double? = nil, metric: Bool = false) {
        self.power3s = power3s
        self.heartRate = heartRate
        self.speed = speed
        self.cadence = cadence
        self.metric = metric
    }
}

/// The ActiveLook app's 4-data page: power and heart rate on two big lines,
/// speed and cadence side by side below. Each field is a layout from the
/// "ALooK" configuration (icon included) at that page's position.
public enum GlassesDashboard {
    public struct Field: Hashable, Sendable {
        public let layout: UInt8
        public let x: UInt16
        public let y: UInt8
    }

    public static let power = Field(layout: 113, x: 30, y: 149)    // power_3s_two_data, "4D Full H"
    public static let heartRate = Field(layout: 83, x: 30, y: 80)  // heartbeat_two_data, "4D Full L"
    public static let speed = Field(layout: 44, x: 157, y: 33)     // speed_half, "3D Half L1"
    public static let cadence = Field(layout: 55, x: 30, y: 33)    // cadence_half, "3D Half L2"

    /// Each field and the text to draw in it, in drawing order.
    public static func fields(_ m: GlassesMetrics) -> [(field: Field, text: String)] {
        let speedInUnits = m.speed.map { m.metric ? $0 * 3.6 : $0 * 2.236936 }
        return [
            (power, aligned(whole(m.power3s))),
            (heartRate, aligned(whole(m.heartRate.map(Double.init)))),
            (speed, aligned(speedInUnits.map { String(format: "%.1f", min($0, 99.9)) } ?? "--")),
            (cadence, aligned(whole(m.cadence))),
        ]
    }

    /// Right-aligns a value in the layouts' "four digits and a separator"
    /// slot with the fonts' invisible ghost characters: `$` is as wide as a
    /// digit, `&` as wide as `.` or `:`.
    public static func aligned(_ value: String) -> String {
        let hasSeparator = value.contains { $0 == "." || $0 == ":" }
        let digitWidths = value.filter { $0 != "." && $0 != ":" }.count
        return (hasSeparator ? "" : "&") + String(repeating: "$", count: max(0, 4 - digitWidths)) + value
    }

    private static func whole(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return String(min(9999, max(0, Int(value.rounded()))))
    }
}

private func bytes(_ value: Int16) -> [UInt8] { bytes(UInt16(bitPattern: value)) }
private func bytes(_ value: UInt16) -> [UInt8] { [UInt8(value >> 8), UInt8(value & 0xFF)] }

/// ASCII only, NUL-terminated, as the glasses expect.
private func cString(_ string: String) -> [UInt8] {
    Array(string.utf8.filter { $0 < 0x80 }) + [0]
}
