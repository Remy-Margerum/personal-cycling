import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // URLRequest lives here on Linux
#endif

/// Uploading rides to Intervals.icu, which feeds remymargerum.com/cycling:
/// the request, how to read the response, and the record of which rides
/// still need uploading.
///
/// API: POST /api/v1/athlete/0/activities (multipart "file"), HTTP Basic
/// auth with username "API_KEY" and the athlete's key as the password.
/// Intervals.icu de-duplicates uploads by a hash of the file (201 when an
/// activity was created, 200 when it was a duplicate), so retrying an upload
/// never creates a second activity.
public enum Intervals {
    public static let uploadURL = "https://intervals.icu/api/v1/athlete/0/activities"

    public static func uploadRequest(file: Data, filename: String, name: String, externalID: String,
                                     apiKey: String, boundary: String = "Boundary-\(UUID().uuidString)") -> URLRequest {
        var components = URLComponents(string: uploadURL)!
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "device_name", value: "Raggio (iPhone)"),
            URLQueryItem(name: "external_id", value: externalID),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Basic \(Data("API_KEY:\(apiKey)".utf8).base64EncodedString())",
                         forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: application/vnd.garmin.tcx+xml\r\n\r\n".utf8))
        body.append(file)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return request
    }

    public enum UploadOutcome: Equatable, Sendable {
        case created(activityID: String?)
        /// Intervals.icu already had this file.
        case duplicate(activityID: String?)

        public var activityID: String? {
            switch self {
            case let .created(id), let .duplicate(id): id
            }
        }
    }

    public enum UploadError: Error, Equatable, LocalizedError, Sendable {
        /// 401/403: the API key is wrong or was revoked.
        case unauthorized
        /// Another 4xx: Intervals.icu refused the request or the file.
        case rejected(status: Int, message: String)
        /// 5xx or no HTTP response: worth retrying later.
        case unavailable(status: Int)

        public var errorDescription: String? {
            switch self {
            case .unauthorized:
                "Intervals.icu didn't accept the API key. Check it in Settings."
            case let .rejected(status, message):
                "Intervals.icu returned \(status): \(message.prefix(200))"
            case let .unavailable(status):
                "Intervals.icu isn't responding (\(status)). Will retry."
            }
        }
    }

    /// Reads an upload response: the new (or existing) activity's ID, or why it failed.
    public static func outcome(status: Int, body: Data) throws -> UploadOutcome {
        switch status {
        case 200, 201:
            struct Response: Decodable {
                struct Activity: Decodable { let id: String? }
                let id: String?
                let activities: [Activity]?
            }
            let response = try? JSONDecoder().decode(Response.self, from: body)
            let id = response?.activities?.first?.id ?? response?.id
            return status == 201 ? .created(activityID: id) : .duplicate(activityID: id)
        case 401, 403:
            throw UploadError.unauthorized
        case 400..<500:
            throw UploadError.rejected(status: status, message: String(decoding: body, as: UTF8.self))
        default:
            throw UploadError.unavailable(status: status)
        }
    }

    /// The Intervals.icu page for an activity.
    public static func activityURL(_ id: String) -> URL? {
        URL(string: "https://intervals.icu/activities/\(id)")
    }

    public enum UploadState: Codable, Equatable, Sendable {
        /// Waiting for its first attempt.
        case queued
        /// The last attempt failed; it's retried on the next sync.
        case failed(String)
        case uploaded(activityID: String?, at: Date)
    }

    /// Which rides were queued for upload and how far they got. Rides that
    /// were never queued (saved before auto-upload, or with it off) aren't
    /// in it and are left alone.
    public struct UploadLog: Codable, Equatable, Sendable {
        private var states: [String: UploadState] = [:]

        public init() {}

        public subscript(ride: UUID) -> UploadState? { states[ride.uuidString] }

        /// Queues a ride, unless it's already uploaded.
        public mutating func queue(_ ride: UUID) {
            if case .uploaded = states[ride.uuidString] { return }
            if states[ride.uuidString] == nil { states[ride.uuidString] = .queued }
        }

        public mutating func record(_ state: UploadState, for ride: UUID) {
            states[ride.uuidString] = state
        }

        /// The rides (of those given, in that order) still to upload.
        public func pending(among rides: [UUID]) -> [UUID] {
            rides.filter { ride in
                switch states[ride.uuidString] {
                case .queued, .failed: true
                case .uploaded, nil: false
                }
            }
        }
    }
}
