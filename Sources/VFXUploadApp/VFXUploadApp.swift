import SwiftUI
import UniformTypeIdentifiers
import VFXUploadCore

@main
struct VFXUploadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("VFX Upload", id: "main") {
            MenuBarContentView(appState: appDelegate.appState)
                .frame(minWidth: 380, idealWidth: 420, minHeight: 300)
        }
        .defaultSize(width: 420, height: 500)
        .commands {
            CommandGroup(replacing: .newItem) {
                AddFilesButton(appState: appDelegate.appState)
            }
            UploadCommands(appState: appDelegate.appState)
        }

        Settings {
            SettingsView(appState: appDelegate.appState)
        }

        MenuBarExtra("VFX Upload", systemImage: "arrow.up.circle.fill") {
            MenuBarDropdown(appState: appDelegate.appState)
        }
    }
}

// MARK: - Command Helpers

struct AddFilesButton: View {
    @Environment(\.openWindow) private var openWindow
    let appState: AppState

    var body: some View {
        Button("Add Files\u{2026}") {
            openWindow(id: "main")
            appState.showFilePicker = true
        }
        .keyboardShortcut("o")
    }
}

struct UploadCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandMenu("Upload") {
            Button("Tag All") { appState.startTagging() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(!appState.canTag)

            Button("Upload All") { appState.startUpload() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!appState.canUpload)

            Divider()

            Button("Clear Completed") { appState.clearCompleted() }
        }
    }
}

// MARK: - Menu Bar Dropdown

struct MenuBarDropdown: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    private var completedJobs: [UploadJob] {
        appState.jobs.filter { $0.status == .completed }
    }

    private var activeJobs: [UploadJob] {
        appState.jobs.filter { !$0.status.isTerminal }
    }

    private var failedJobs: [UploadJob] {
        appState.jobs.filter {
            if case .failed = $0.status { return true }
            return false
        }
    }

    var body: some View {
        // Status summary
        if appState.uploadManager.isTagging {
            Label(
                "Tagging \(appState.uploadManager.completedCount)/\(appState.uploadManager.totalCount)",
                systemImage: "paintpalette"
            )
            .disabled(true)
        } else if appState.uploadManager.isUploading {
            Label(
                "Uploading \(appState.uploadManager.completedCount)/\(appState.uploadManager.totalCount)",
                systemImage: "arrow.up.circle"
            )
            .disabled(true)
        } else if !activeJobs.isEmpty {
            Label(
                "\(activeJobs.count) pending",
                systemImage: "clock"
            )
            .disabled(true)
        }

        // Completed uploads
        if !completedJobs.isEmpty {
            Section("Uploaded") {
                // Most recent first, limit to 10
                ForEach(completedJobs.suffix(10).reversed()) { job in
                    Button {
                        if let uri = job.s3URI {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(uri, forType: .string)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.fileName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let uri = job.s3URI {
                                Text(uri)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }

                Button("Copy Latest S3 URI") {
                    if let latest = completedJobs.last, let uri = latest.s3URI {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(uri, forType: .string)
                    }
                }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(completedJobs.last?.s3URI == nil)

                Button("Clear Completed") {
                    appState.clearCompleted()
                }
            }
        }

        // Failed uploads
        if !failedJobs.isEmpty {
            Section("Failed") {
                ForEach(failedJobs.prefix(5)) { job in
                    Label {
                        Text(job.fileName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                    .disabled(true)
                }
            }
        }

        Divider()

        Button("Open Window") {
            openWindow(id: "main")
            NSApp.activate()
        }
        .keyboardShortcut("o")

        Button("Choose Files\u{2026}") {
            openWindow(id: "main")
            NSApp.activate()
            appState.showFilePicker = true
        }
        .keyboardShortcut("n")

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState: AppState

    override init() {
        if CommandLine.arguments.contains("--clean-install") {
            DependencyCheck.simulateCleanInstall = true
        }
        self.appState = AppState()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon — menu bar + window only
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if appState.uploadManager.isTagging || appState.uploadManager.isUploading {
            let alert = NSAlert()
            alert.messageText = "Work in Progress"
            alert.informativeText = "Please wait for tagging/uploads to finish before quitting."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }
}
