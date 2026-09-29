import Foundation
import RideKit

/// Diagnostic log for the first hardware rides: raw power-meter packets,
/// heart-rate samples, GPS fixes and every connection or session state
/// change. Lines go to one file per day in Documents/Logs (shareable from
/// Settings → Debug log, and visible in the Files app) and the latest ones
/// stay in memory for the on-screen view.
///
/// GPS lines carry accuracy, speed and step distance but no coordinates, so
/// a shared log doesn't reveal where you ride.
final class DebugLog: @unchecked Sendable {
    static let shared = DebugLog()

    enum Category: String { case app, power, hr, gps, ride }

    let folder: URL
    private let queue = DispatchQueue(label: "DebugLog")
    // Everything below is only touched on `queue`.
    private var ring = LogRing(capacity: 2000)
    private var handle: FileHandle?
    private var handleDay: String?
    private static let keepDays = 7

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = docs.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        queue.async { self.deleteOldFiles() }
    }

    func log(_ category: Category, _ message: String) {
        let now = Date()
        queue.async {
            let line = DebugFormat.line(date: now, category: category.rawValue, message: message)
            self.ring.append(line)
            self.write(line, at: now)
        }
    }

    /// Newest last.
    func recentLines(limit: Int = 500) -> [String] {
        queue.sync { Array(ring.lines.suffix(limit)) }
    }

    /// Log files, newest first.
    func files() -> [URL] {
        queue.sync { logFiles().sorted { $0.lastPathComponent > $1.lastPathComponent } }
    }

    func clear() {
        queue.sync {
            try? handle?.close()
            handle = nil
            handleDay = nil
            ring.removeAll()
            for file in logFiles() { try? FileManager.default.removeItem(at: file) }
        }
    }

    // MARK: Files

    private func write(_ line: String, at date: Date) {
        let day = Self.dayString(date)
        if handle == nil || handleDay != day {
            try? handle?.close()
            let url = folder.appendingPathComponent("debug-\(day).log")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: url)
            _ = try? handle?.seekToEnd()
            handleDay = day
        }
        try? handle?.write(contentsOf: Data((line + "\n").utf8))
    }

    private func logFiles() -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.pathExtension == "log" }
    }

    private func deleteOldFiles() {
        let cutoff = "debug-\(Self.dayString(Date().addingTimeInterval(-Double(Self.keepDays) * 86_400))).log"
        for file in logFiles() where file.lastPathComponent < cutoff {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func dayString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
