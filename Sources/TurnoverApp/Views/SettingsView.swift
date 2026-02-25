import SwiftUI
import TurnoverCore

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var savedConfirmation = false

    var body: some View {
        VSplitView {
            // JSON editor — primary content, takes most of the space
            VStack(spacing: 0) {
                TextEditor(text: $appState.configText)
                    .font(.system(size: 11, design: .monospaced))

                // Status bar
                HStack(spacing: 12) {
                    if let error = appState.configError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(error)
                            .foregroundStyle(.red)
                    } else if savedConfirmation {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(appState.projects.count) project\(appState.projects.count == 1 ? "" : "s") loaded")
                    } else {
                        Text("\(appState.projects.count) project\(appState.projects.count == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !appState.projects.isEmpty {
                        Button("Clear") {
                            appState.removeAllProjects()
                        }
                    }

                    Button("Save") {
                        appState.saveConfigText()
                        if appState.configError == nil {
                            savedConfirmation = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                savedConfirmation = false
                            }
                        }
                    }
                    .keyboardShortcut("s", modifiers: .command)
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.bar)
            }
            .frame(minHeight: 200)

            // Settings below the editor
            Form {
                Picker("Default Color Space", selection: Binding(
                    get: { appState.selectedColorSpace },
                    set: { appState.selectedColorSpace = $0 }
                )) {
                    ForEach(ColorSpace.allCases, id: \.self) { cs in
                        Text(cs.displayName).tag(cs)
                    }
                }

                Toggle("Audio Muxing", isOn: $appState.enableAudioMuxing)
                    .help("Automatically mix audio from plates folder into uploads")

                HStack {
                    Text("Version")
                    Spacer()
                    Text(appState.currentVersion)
                        .foregroundStyle(.secondary)
                    if let update = appState.availableUpdate {
                        Button("v\(update.version) available") {
                            appState.openUpdate()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button("Check") {
                            Task { await appState.checkForUpdates() }
                        }
                        .buttonStyle(.plain)
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 140, maxHeight: 160)
        }
        .frame(width: 560, height: 440)
    }
}
