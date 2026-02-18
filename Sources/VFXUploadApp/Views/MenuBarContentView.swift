import SwiftUI
import VFXUploadCore

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Group {
            if !appState.isAuthenticated {
                CredentialView()
            } else if appState.uploadManager.isTagging || appState.uploadManager.isUploading {
                UploadProgressView()
            } else {
                mainContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if appState.jobs.contains(where: { $0.status == .completed }) {
                    Button("Clear Done") { appState.clearCompleted() }
                }
            }
            ToolbarItem(placement: .status) {
                if appState.uploadManager.isTagging {
                    Text("\(appState.uploadManager.completedCount)/\(appState.uploadManager.totalCount) tagged")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if appState.uploadManager.isUploading {
                    Text("\(appState.uploadManager.completedCount)/\(appState.uploadManager.totalCount) uploaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if case .valid(let account) = appState.credentialStatus {
                    Label(account, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .environmentObject(appState)
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
                .controlSize(.large)
            } else if appState.canUpload {
                Button { appState.startUpload() } label: {
                    Label("Upload All", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
