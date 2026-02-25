import SwiftUI
import TurnoverCore

struct UpdateSheetView: View {
    @ObservedObject var appState: AppState
    let update: AppRelease

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.app")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            Text("Update Available")
                .font(.headline)

            Text("v\(appState.currentVersion) \u{2192} v\(update.version)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            switch appState.updateProgress {
            case .idle:
                HStack(spacing: 12) {
                    Button("Not Now") {
                        appState.showUpdateSheet = false
                    }
                    .buttonStyle(.bordered)

                    Button("Install & Relaunch") {
                        appState.installUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                }

            case .downloading(let progress):
                VStack(spacing: 6) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text("Downloading\u{2026} \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .installing:
                VStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing\u{2026}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .restarting:
                VStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Relaunching\u{2026}")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .failed(let msg):
                VStack(spacing: 8) {
                    Label(msg, systemImage: "xmark.circle")
                        .foregroundStyle(.red)
                        .font(.caption)

                    HStack(spacing: 12) {
                        Button("Cancel") {
                            appState.updateProgress = .idle
                            appState.showUpdateSheet = false
                        }
                        .buttonStyle(.bordered)

                        Button("Retry") {
                            appState.updateProgress = .idle
                            appState.installUpdate()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Download Manually") {
                            appState.openUpdate()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 320)
        .interactiveDismissDisabled(appState.updateProgress != .idle)
    }
}
