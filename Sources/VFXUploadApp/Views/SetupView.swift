import SwiftUI
import VFXUploadCore

struct SetupView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)

                Text("First-Run Setup")
                    .font(.headline)

                Text("Complete these steps to get started.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    ffmpegSection
                    Divider()
                    awsCliSection
                    Divider()
                    ssoConfigSection
                }

                if !appState.setupOutput.isEmpty {
                    outputView
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - ffmpeg / ffprobe

    private var ffmpegSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                "ffmpeg & ffprobe",
                done: appState.dependencyStatus.hasFFmpeg && appState.dependencyStatus.hasFFprobe
            )

            HStack(spacing: 6) {
                statusDot(appState.dependencyStatus.hasFFmpeg)
                Text("ffmpeg")
                    .font(.caption.monospaced())
                if let path = appState.dependencyStatus.ffmpegPath {
                    Text(path).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                statusDot(appState.dependencyStatus.hasFFprobe)
                Text("ffprobe")
                    .font(.caption.monospaced())
                if let path = appState.dependencyStatus.ffprobePath {
                    Text(path).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !appState.dependencyStatus.hasFFmpeg || !appState.dependencyStatus.hasFFprobe {
                if appState.isDownloadingFFmpeg {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: { appState.downloadFFmpeg() }) {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - AWS CLI

    private var awsCliSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("AWS CLI", done: appState.dependencyStatus.hasAWS)

            HStack(spacing: 6) {
                statusDot(appState.dependencyStatus.hasAWS)
                Text("aws")
                    .font(.caption.monospaced())
                if let path = appState.dependencyStatus.awsPath {
                    Text(path).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !appState.dependencyStatus.hasAWS {
                if appState.isInstallingAWS {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    HStack(spacing: 8) {
                        Button(action: { appState.installAWSCLI() }) {
                            Label("Install", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("Check Again") { appState.recheckDependencies() }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - SSO Config

    private var ssoConfigSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("AWS SSO Config", done: appState.dependencyStatus.hasSSOConfig)

            if appState.dependencyStatus.hasSSOConfig {
                HStack(spacing: 6) {
                    statusDot(true)
                    Text("~/.aws/config")
                        .font(.caption.monospaced())
                    Text("SSO configured")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    formField("SSO Start URL", text: $appState.ssoStartURL, placeholder: "https://your-company.awsapps.com/start")
                    formField("Region", text: $appState.ssoRegion, placeholder: "us-east-1")
                    formField("Account ID", text: $appState.ssoAccountID, placeholder: "123456789012")
                    formField("Role Name", text: $appState.ssoRoleName, placeholder: "AdministratorAccess")

                    Button(action: { appState.saveSSOConfig() }) {
                        Label("Save Config", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(appState.ssoStartURL.isEmpty || appState.ssoAccountID.isEmpty || appState.ssoRoleName.isEmpty)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
            Text(title)
                .font(.subheadline.bold())
        }
    }

    private func statusDot(_ ok: Bool) -> some View {
        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(ok ? .green : .red)
            .font(.caption)
    }

    private func formField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
    }

    private var outputView: some View {
        ScrollView {
            Text(appState.setupOutput)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 100)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
