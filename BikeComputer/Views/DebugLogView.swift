import SwiftUI

/// Settings → Debug log: the latest log lines, newest first, plus a share
/// button for the log files (send them to Claude when something's wrong).
struct DebugLogView: View {
    @State private var lines: [String] = []
    @State private var files: [URL] = []
    @State private var confirmClear = false

    var body: some View {
        List {
            if lines.isEmpty {
                Text("Nothing logged yet.").foregroundStyle(.secondary)
            }
            ForEach(Array(lines.reversed().enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Debug log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(items: files) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(files.isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Clear log", systemImage: "trash", role: .destructive) { confirmClear = true }
            }
        }
        .confirmationDialog("Delete all debug logs?", isPresented: $confirmClear) {
            Button("Delete logs", role: .destructive) {
                DebugLog.shared.clear()
                refresh()
            }
        }
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refresh() {
        lines = DebugLog.shared.recentLines()
        files = DebugLog.shared.files()
    }
}
