import SwiftUI
import UniformTypeIdentifiers
import VFXUploadCore

struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var showProjectImporter = false
    @State private var importError: String?

    var body: some View {
        Form {
            Section {
                Text("Complete these steps to get started.")
                    .foregroundStyle(.secondary)
            }

            Section("ffmpeg & ffprobe") {
                depRow("ffmpeg", ok: appState.dependencyStatus.hasFFmpeg, detail: appState.dependencyStatus.ffmpegPath)
                depRow("ffprobe", ok: appState.dependencyStatus.hasFFprobe, detail: appState.dependencyStatus.ffprobePath)

                if !appState.dependencyStatus.hasFFmpeg || !appState.dependencyStatus.hasFFprobe {
                    if appState.isDownloadingFFmpeg {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Download\u{2026}") { appState.downloadFFmpeg() }
                    }
                }
            }

            Section("AWS CLI") {
                depRow("aws", ok: appState.dependencyStatus.hasAWS, detail: appState.dependencyStatus.awsPath)

                if !appState.dependencyStatus.hasAWS {
                    if appState.isInstallingAWS {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        HStack {
                            Button("Install\u{2026}") { appState.installAWSCLI() }
                            Button("Check Again") { appState.recheckDependencies() }
                        }
                    }
                }
            }

            Section("AWS SSO Config") {
                if appState.dependencyStatus.hasSSOConfig {
                    depRow("~/.aws/config", ok: true, detail: "SSO configured")
                } else {
                    Text("Run `aws configure sso` in Terminal — just enter your start URL and follow the prompts.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Configure in Terminal\u{2026}") { appState.openSSOConfigInTerminal() }
                        Button("Check Again") { appState.recheckDependencies() }
                    }
                }
            }

            Section("Projects") {
                if appState.projects.isEmpty {
                    Label("No project config loaded", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.projects) { project in
                        Label(project.displayName, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Button("Import Config\u{2026}") { showProjectImporter = true }

                if let error = importError {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            if !appState.setupOutput.isEmpty {
                Section("Output") {
                    Text(appState.setupOutput)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $showProjectImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    try appState.importProjects(from: url)
                    importError = nil
                } catch {
                    importError = "Import failed: \(error.localizedDescription)"
                }
            case .failure(let error):
                importError = "File picker error: \(error.localizedDescription)"
            }
        }
    }

    private func depRow(_ name: String, ok: Bool, detail: String?) -> some View {
        LabeledContent {
            if let detail {
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label(name, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
        }
    }
}
