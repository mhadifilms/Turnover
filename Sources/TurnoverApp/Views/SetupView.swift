import SwiftUI
import TurnoverCore

struct SetupView: View {
    @EnvironmentObject var appState: AppState

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
                TextEditor(text: $appState.configText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)

                Button("Save") {
                    appState.saveConfigText()
                }

                if let error = appState.configError {
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
