import SwiftUI
import TurnoverCore

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if !appState.dependencyStatus.isReady {
                SetupView()
            } else if !appState.isAuthenticated {
                CredentialView()
            } else {
                mainContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .status) {
                statusText
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if let update = appState.availableUpdate {
                    Button { appState.openUpdate() } label: {
                        Label("v\(update.version)", systemImage: "arrow.down.circle")
                    }
                    .help("Update available — click to download")
                }
                if appState.jobs.contains(where: { $0.status == .completed }) {
                    Button("Clear Done") { appState.clearCompleted() }
                }
                Button(action: { openSettings() }) {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Settings\u{2026}")
            }
        }
        .environmentObject(appState)
    }

    @ViewBuilder
    private var statusText: some View {
        if appState.uploadManager.isTagging {
            Text("\(appState.uploadManager.completedCount)/\(appState.uploadManager.totalCount) tagged")
        } else if appState.uploadManager.isUploading {
            Text("\(appState.uploadManager.completedCount)/\(appState.uploadManager.totalCount) uploaded")
        } else {
            EmptyView()
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            DropZoneView()

            if appState.hasJobs {
                Divider()

                if appState.uploadManager.isTagging || appState.uploadManager.isUploading {
                    progressBar
                        .padding(12)
                    Divider()
                }

                FileListView()
                actionBar
            }
        }
    }

    private var progressBar: some View {
        VStack(spacing: 4) {
            ProgressView(
                value: Double(appState.uploadManager.completedCount),
                total: max(Double(appState.uploadManager.totalCount), 1)
            )
            .progressViewStyle(.linear)
            .accessibilityLabel("Overall progress")
            .accessibilityValue("\(appState.uploadManager.completedCount) of \(appState.uploadManager.totalCount) completed")

            HStack {
                Text(appState.uploadManager.isTagging ? "Tagging\u{2026}" : "Uploading\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(appState.uploadManager.completedCount)/\(appState.uploadManager.totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Cancel") { appState.cancelOperation() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var actionBar: some View {
        HStack {
            Spacer()

            if appState.canTag {
                Button { appState.startTagging() } label: {
                    Label("Tag All", systemImage: "paintpalette")
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
            } else if appState.canUpload {
                Button { appState.startUpload() } label: {
                    Label("Upload All", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
