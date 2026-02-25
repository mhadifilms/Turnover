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

            // Step 1: ffmpeg & ffprobe
            stepSection(
                number: 1,
                title: "ffmpeg & ffprobe",
                done: appState.dependencyStatus.hasFFmpeg && appState.dependencyStatus.hasFFprobe
            ) {
                depRow("ffmpeg", ok: appState.dependencyStatus.hasFFmpeg, detail: appState.dependencyStatus.ffmpegPath)
                depRow("ffprobe", ok: appState.dependencyStatus.hasFFprobe, detail: appState.dependencyStatus.ffprobePath)

                if appState.isDownloadingFFmpeg {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(appState.setupOutput.components(separatedBy: "\n").last(where: { !$0.isEmpty }) ?? "Downloading\u{2026}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Button("Download") { appState.downloadFFmpeg() }
                }
            }

            // Step 2: AWS CLI
            stepSection(
                number: 2,
                title: "AWS CLI",
                done: appState.dependencyStatus.hasAWS
            ) {
                depRow("aws", ok: appState.dependencyStatus.hasAWS, detail: appState.dependencyStatus.awsPath)

                if appState.isInstallingAWS {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting for installer\u{2026}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Button("Install") { appState.installAWSCLI() }
                        Button("Check Again") { appState.recheckDependencies() }
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Step 3: AWS SSO Config
            stepSection(
                number: 3,
                title: "AWS SSO Config",
                done: appState.dependencyStatus.hasSSOConfig
            ) {
                if appState.dependencyStatus.hasSSOConfig {
                    depRow("~/.aws/config", ok: true, detail: "SSO configured")
                } else {
                    Text("Open Terminal and run **aws configure sso** — enter your start URL and follow the prompts.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Open Terminal") { appState.openSSOConfigInTerminal() }
                        Button("Check Again") { appState.recheckDependencies() }
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Step 4: Projects
            stepSection(
                number: 4,
                title: "Projects",
                done: appState.dependencyStatus.hasProjects
            ) {
                if appState.configText == "[]" || appState.configText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Paste your project configuration JSON below.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                TextEditor(text: $appState.configText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)

                HStack {
                    Button("Save") { appState.saveConfigText() }
                        .buttonStyle(.borderedProminent)

                    if let error = appState.configError {
                        Label(error, systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                            .font(.caption)
                            .lineLimit(2)
                    }
                }
            }

            if let error = appState.setupError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func stepSection<Content: View>(
        number: Int,
        title: String,
        done: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            if done {
                Label(title, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                content()
            }
        } header: {
            HStack(spacing: 6) {
                Text("\(number)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(done ? .green : .white)
                    .frame(width: 18, height: 18)
                    .background(done ? Color.green.opacity(0.2) : Color.accentColor)
                    .clipShape(Circle())
                Text(title)
            }
        }
    }

    private func depRow(_ name: String, ok: Bool, detail: String?) -> some View {
        LabeledContent {
            if let detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } label: {
            Label(name, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
        }
    }
}
