import RideKit
import SwiftUI

struct HistoryView: View {
    @Environment(RideRecorder.self) private var recorder
    @AppStorage("useMetric") private var useMetric = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(recorder.store.rides) { ride in
                    NavigationLink(value: ride.id) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(ride.startDate, format: .dateTime.weekday().month().day().hour().minute())
                                let units = Units(metric: useMetric)
                                Text("\(units.distance(ride.summary.distance)) \(units.distanceUnit) · \(Units.duration(ride.movingTime))")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            UploadIcon(state: recorder.intervals.state(of: ride),
                                       uploading: recorder.intervals.uploading.contains(ride.id))
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { recorder.store.rides[$0] }.forEach(recorder.store.delete)
                }
            }
            .overlay {
                if recorder.store.rides.isEmpty {
                    ContentUnavailableView("No rides yet", systemImage: "bicycle")
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: UUID.self) { id in
                if let ride = recorder.store.rides.first(where: { $0.id == id }) {
                    RideDetailView(ride: ride)
                }
            }
        }
    }
}

struct RideDetailView: View {
    let ride: Ride
    @Environment(RideRecorder.self) private var recorder
    @AppStorage("useMetric") private var useMetric = false

    var body: some View {
        let s = ride.summary
        let units = Units(metric: useMetric)
        List {
            Section("Summary") {
                LabeledContent("Distance", value: "\(units.distance(s.distance)) \(units.distanceUnit)")
                LabeledContent("Moving time", value: Units.duration(s.movingTime))
                LabeledContent("Climbed", value: "\(units.elevation(s.elevationGain)) \(units.elevationUnit)")
                LabeledContent("Avg speed", value: "\(units.speed(s.averageSpeed)) \(units.speedUnit)")
                LabeledContent("Max speed", value: "\(units.speed(s.maxSpeed)) \(units.speedUnit)")
            }
            Section("Power & heart rate") {
                LabeledContent("Avg power", value: "\(Units.whole(s.averagePower)) W")
                LabeledContent("Normalized power", value: "\(Units.whole(s.normalizedPower)) W")
                LabeledContent("Max power", value: "\(s.maxPower.map(String.init) ?? "--") W")
                LabeledContent("Avg cadence", value: "\(Units.whole(s.averageCadence)) rpm")
                LabeledContent("Avg heart rate", value: "\(Units.whole(s.averageHeartRate)) bpm")
                LabeledContent("Max heart rate", value: "\(s.maxHeartRate.map(String.init) ?? "--") bpm")
            }
            Section {
                ShareLink(item: recorder.store.tcxURL(for: ride)) {
                    Label("Export TCX", systemImage: "square.and.arrow.up")
                }
                intervalsRow
            }
        }
        .navigationTitle(ride.startDate.formatted(date: .abbreviated, time: .shortened))
    }

    @ViewBuilder private var intervalsRow: some View {
        let uploading = recorder.intervals.uploading.contains(ride.id)
        switch recorder.intervals.state(of: ride) {
        case let .uploaded(activityID, _) where !uploading:
            if let activityID, let url = Intervals.activityURL(activityID) {
                Link(destination: url) {
                    Label("Open in Intervals.icu", systemImage: "checkmark.icloud")
                }
            } else {
                Label("Uploaded to Intervals.icu", systemImage: "checkmark.icloud")
            }
        case let state:
            Button {
                Task { await recorder.intervals.upload(ride) }
            } label: {
                if uploading {
                    Label("Uploading…", systemImage: "icloud.and.arrow.up")
                } else if case .failed = state {
                    Label("Retry upload to Intervals.icu", systemImage: "arrow.clockwise.icloud")
                } else {
                    Label("Upload to Intervals.icu", systemImage: "icloud.and.arrow.up")
                }
            }
            .disabled(uploading)
            if case let .failed(message) = state {
                Text(message).font(.footnote).foregroundStyle(.orange)
            }
        }
    }
}

/// Intervals.icu status in the ride list: nothing if the ride was never
/// queued for upload.
private struct UploadIcon: View {
    let state: Intervals.UploadState?
    let uploading: Bool

    var body: some View {
        switch state {
        case .uploaded where !uploading:
            Image(systemName: "checkmark.icloud").foregroundStyle(.secondary)
        case .failed where !uploading:
            Image(systemName: "exclamationmark.icloud").foregroundStyle(.orange)
        case .some:
            Image(systemName: "icloud.and.arrow.up").foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }
}
