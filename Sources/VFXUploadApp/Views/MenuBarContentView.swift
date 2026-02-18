import SwiftUI
import VFXUploadCore

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if !appState.dependencyStatus.isReady {
                SetupView()
            } else if !appState.isAuthenticated {
                CredentialView()
            } else if appState.uploadManager.isTagging || appState.uploadManager.isUploading {
                UploadProgressView()
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
                FileListView()
                actionBar
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
